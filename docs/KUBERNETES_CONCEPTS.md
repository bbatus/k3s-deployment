# Kubernetes Concepts - Interview Cheat Sheet

Bu dokümanda, interview'da sorulabilecek Kubernetes kavramları ve projemizdeki somut örnekleri bulabilirsiniz.

---

## 📋 İçindekiler

- [Kubernetes Architecture](#kubernetes-architecture)
- [Core Components](#core-components)
- [Workload Resources](#workload-resources)
- [Networking](#networking)
- [Storage](#storage)
- [Configuration & Secrets](#configuration--secrets)
- [Scheduling & Automation](#scheduling--automation)
- [Project-Specific Questions](#project-specific-questions)

---

## Kubernetes Architecture

### Master Node (Control Plane) Components

**S: Master node'da hangi componentler var ve ne işe yarar?**

C: Master node, cluster'ı yöneten control plane componentlerini barındırır:

1. **kube-apiserver**
   - Kubernetes API'sini expose eder
   - Tüm componentler buraya request atar
   - kubectl komutları buraya gelir
   - Bizim projede: `kubectl get pods` dediğimizde API server'a gidiyoruz

2. **etcd**
   - Distributed key-value store
   - Cluster'ın tüm state'ini saklar
   - Backup kritik (etcd backup = cluster backup)
   - Bizim projede: PostgreSQL secretları, PVC bilgileri burada

3. **kube-scheduler**
   - Yeni pod'ları hangi node'a yerleştireceğine karar verir
   - Resource requirements'a bakar (CPU, memory)
   - Bizim projede: PostgreSQL pod'unu node'a scheduler yerleştirdi

4. **kube-controller-manager**
   - Çeşitli controller'ları çalıştırır
   - ReplicaSet, Deployment, StatefulSet controller'ları
   - Desired state vs actual state'i reconcile eder
   - Bizim projede: StatefulSet controller PostgreSQL-0 pod'unu yönetiyor

5. **cloud-controller-manager** (opsiyonel)
   - Cloud provider'a özgü logic
   - LoadBalancer service'leri cloud LB'ye bağlar
   - Bizim projede: Yok (local k3s)

### Worker Node Components

**S: Worker node'da hangi componentler var?**

C: Worker node'lar pod'ları çalıştırır:

1. **kubelet**
   - Her node'da çalışır
   - Pod'ları başlatır ve monitor eder
   - Container runtime ile konuşur
   - Bizim projede: PostgreSQL container'ını kubelet başlattı

2. **kube-proxy**
   - Network proxy, her node'da çalışır
   - Service'lerin network routing'ini yapar
   - iptables veya IPVS kullanır
   - Bizim projede: NodePort 30432'yi PostgreSQL pod'una route ediyor

3. **Container Runtime**
   - Container'ları çalıştırır (Docker, containerd, CRI-O)
   - k3s containerd kullanır
   - Bizim projede: PostgreSQL image'ını containerd çalıştırıyor

---

## Core Components

### Pod

**S: Pod nedir, neden container değil?**

C: Pod, Kubernetes'in en küçük deployment unit'i:
- Bir veya daha fazla container içerir
- Aynı network namespace'i paylaşırlar (localhost ile konuşabilirler)
- Aynı storage volume'leri paylaşabilirler
- Ephemeral (geçici), restart olursa yeni IP alır

**Bizim projede:**
```bash
# PostgreSQL pod
kubectl get pod postgresql-0
# İçinde 1 container var: postgresql
```

### ReplicaSet

**S: ReplicaSet ne işe yarar?**

C: Belirtilen sayıda pod replica'sının her zaman çalışmasını garanti eder:
- Pod ölürse yenisini başlatır
- Scale up/down yapabilir
- Label selector ile pod'ları bulur

**Bizim projede:**
- Direkt ReplicaSet kullanmıyoruz
- StatefulSet ve Deployment altında otomatik oluşuyor

### Deployment

**S: Deployment nedir, ne zaman kullanılır?**

C: Stateless uygulamalar için:
- ReplicaSet'leri yönetir
- Rolling update yapar
- Rollback yapabilir
- Pod'lar interchangeable (hangisi olursa olsun)

**Bizim projede kullanmıyoruz çünkü:**
- PostgreSQL ve Redis stateful
- StatefulSet kullanıyoruz

### StatefulSet

**S: StatefulSet nedir, Deployment'tan farkı ne?**

C: Stateful uygulamalar için:
- Her pod'un unique identity'si var (postgresql-0, postgresql-1)
- Pod'lar sırayla başlar ve durur
- Her pod'un kendi PVC'si var
- Network identity stable (postgresql-0.postgresql.default.svc.cluster.local)

**Bizim projede:**
```bash
# PostgreSQL StatefulSet
kubectl get statefulset
# NAME         READY   AGE
# postgresql   1/1     10m

# Pod name predictable
kubectl get pod postgresql-0
```

**Neden StatefulSet?**
- PostgreSQL database, data persist etmeli
- Pod restart olsa bile aynı PVC'ye bağlanmalı
- Master-replica setup'ta pod identity önemli

### DaemonSet

**S: DaemonSet ne işe yarar?**

C: Her node'da (veya seçili node'larda) bir pod çalıştırır:
- Node eklendikçe otomatik pod oluşur
- Node silinince pod da silinir
- Monitoring, logging, networking için kullanılır

**Bizim projede:**
```bash
# k3s'in kube-proxy'si DaemonSet
kubectl get daemonset -n kube-system
# NAME                      DESIRED   CURRENT   READY
# svclb-traefik-8646d88c    1         1         1
```

**Use case:**
- Log collector (Fluentd) her node'da
- Monitoring agent (Prometheus node-exporter)
- Network plugin (Calico, Flannel)

### Job

**S: Job nedir, ne zaman kullanılır?**

C: Bir kez çalışıp biten task'ler için:
- Completion'a kadar retry eder
- Paralel job'lar çalıştırabilir
- Başarılı olunca pod kalır (log'lar için)

**Bizim projede:**
```bash
# Manuel backup trigger
kubectl create job --from=cronjob/postgresql-backup manual-backup-$(date +%s)
```

### CronJob

**S: CronJob nedir, nasıl çalışır?**

C: Zamanlanmış job'lar için (Linux cron gibi):
- Schedule: cron expression (0 2 * * * = her gün 2:00)
- Her schedule'da yeni Job oluşturur
- Job history tutar (successfulJobsHistoryLimit)

**Bizim projede:**
```yaml
# k8s/backup/backup-cronjob.yaml
schedule: "0 2 * * *"  # Her gün 2:00 AM
concurrencyPolicy: Forbid  # Concurrent backup'a izin verme
```

**Neden CronJob?**
- PostgreSQL backup'ı her gün otomatik alınmalı
- Shell script cron'dan daha güvenilir (pod restart olsa bile çalışır)
- Kubernetes native, monitoring kolay

---

## Networking

### Service Types

**S: Kubernetes'te service type'ları nelerdir ve farkları ne?**

C: 4 tip service var:

#### 1. ClusterIP (Default)

**Ne zaman:** Internal communication
```yaml
service:
  type: ClusterIP
  # Sadece cluster içinden erişilebilir
```

**Bizim projede:**
- PostgreSQL'in internal service'i ClusterIP
- `postgresql.default.svc.cluster.local:5432`
- Pod'lar birbirine bu DNS ile bağlanır

**Avantaj:** Güvenli, external exposure yok
**Dezavantaj:** Cluster dışından erişilemez

#### 2. NodePort

**Ne zaman:** Development, testing, external access gerektiğinde
```yaml
service:
  type: NodePort
  nodePorts:
    postgresql: "30432"  # 30000-32767 arası
```

**Bizim projede:**
- PostgreSQL: 30432
- Redis: 30379
- `localhost:30432` ile bağlanabiliyoruz

**Avantaj:** Basit, cloud provider gerekmez
**Dezavantaj:** 
- Port range sınırlı (30000-32767)
- Her node'un IP'sini bilmek gerekir
- Production'da güvenlik riski (firewall gerekir)

#### 3. LoadBalancer

**Ne zaman:** Production, cloud environment
```yaml
service:
  type: LoadBalancer
  # Cloud provider otomatik LB oluşturur
```

**Bizim projede kullanmıyoruz çünkü:**
- Local k3s, cloud provider yok
- AWS ELB, GCP Load Balancer gerektirir

**Avantaj:** Production-ready, HA, SSL termination
**Dezavantaj:** Cloud'da çalışır, local'de çalışmaz

#### 4. ExternalName

**Ne zaman:** External service'i cluster'a map etmek
```yaml
service:
  type: ExternalName
  externalName: my-database.example.com
```

**Use case:** External RDS'i Kubernetes DNS'e eklemek

### NodePort vs ClusterIP vs LoadBalancer

**S: Neden NodePort kullandınız, güvenli değil mi?**

C: Ödev gereksinimi "cluster dışından erişim" istiyordu:

**Seçenekler:**
1. ❌ ClusterIP: Cluster dışından erişilemez
2. ✅ NodePort: Local VM'de çalışır, basit
3. ❌ LoadBalancer: Cloud provider gerektirir

**Production'da ne yapardık:**
```yaml
# Option 1: Managed Services
# Cloud SQL (PostgreSQL)
# ElastiCache (Redis)
# Kubernetes'e gerek yok

# Option 2: LoadBalancer + Ingress
service:
  type: LoadBalancer
ingress:
  enabled: true
  # NGINX Ingress Controller
  # SSL/TLS termination
  # Domain routing

# Option 3: VPN/Bastion + ClusterIP
service:
  type: ClusterIP
# VPN ile cluster'a bağlan
# Veya bastion host üzerinden
```

**Security best practices:**
- NodePort kullanıyorsak firewall rules ekle
- Specific IP ranges (0.0.0.0/0 değil)
- VPN kullan
- Network policies ekle

### Service Discovery

**S: Pod'lar birbirini nasıl bulur?**

C: Kubernetes DNS:
```bash
# Format: <service-name>.<namespace>.svc.cluster.local

# PostgreSQL internal DNS
postgresql.default.svc.cluster.local:5432

# Redis internal DNS
redis-master.default.svc.cluster.local:6379
```

**Bizim projede:**
```bash
# Backup script PostgreSQL'e bu DNS ile bağlanıyor
pg_dumpall -h postgresql.default.svc.cluster.local -U postgres
```

---

## Storage

### PersistentVolume (PV) vs PersistentVolumeClaim (PVC)

**S: PV ve PVC farkı nedir?**

C: 
- **PV**: Admin'in oluşturduğu storage resource (disk)
- **PVC**: User'ın storage talebi (claim)

**Analoji:** PV = Araba, PVC = Araba kiralama talebi

**Bizim projede:**
```bash
# PVC oluşturuyoruz
kubectl get pvc
# NAME                    STATUS   VOLUME                 CAPACITY
# data-postgresql-0       Bound    pvc-abc123             10Gi
# redis-data-redis-0      Bound    pvc-def456             5Gi
# postgresql-backup-pvc   Bound    pvc-ghi789             20Gi

# PV otomatik oluşuyor (dynamic provisioning)
kubectl get pv
# NAME         CAPACITY   ACCESS MODES   STORAGECLASS   STATUS
# pvc-abc123   10Gi       RWO            local-path     Bound
```

### StorageClass

**S: StorageClass nedir?**

C: Storage'ın nasıl provision edileceğini tanımlar:
- Dynamic provisioning için
- Farklı storage tier'ları (SSD, HDD)
- Cloud provider'a özgü (AWS EBS, GCP PD)

**Bizim projede:**
```yaml
# postgresql-values.yaml
persistence:
  storageClass: local-path  # k3s default
```

**k3s local-path:**
- Node'un local diskini kullanır
- `/var/lib/rancher/k3s/storage/` altında
- Otomatik directory oluşturur
- Single-node için ideal

**Production'da:**
- AWS: `gp3` (SSD), `io2` (high IOPS)
- GCP: `pd-ssd`, `pd-balanced`
- Azure: `managed-premium`

### Access Modes

**S: PVC access mode'ları nelerdir?**

C:
- **ReadWriteOnce (RWO)**: Tek node, read-write
- **ReadOnlyMany (ROX)**: Çok node, read-only
- **ReadWriteMany (RWX)**: Çok node, read-write

**Bizim projede:**
```yaml
persistence:
  accessModes:
    - ReadWriteOnce  # RWO
```

**Neden RWO?**
- PostgreSQL single-node
- Aynı anda sadece 1 pod yazabilir
- RWX gerekmiyor (multi-node write yok)

### Volume Types

**S: Kubernetes'te volume type'ları nelerdir?**

C: Çok çeşit var, en yaygınları:

1. **emptyDir**: Geçici, pod ile birlikte silinir
2. **hostPath**: Node'un dosya sistemini mount eder
3. **persistentVolumeClaim**: PVC kullanır (bizim seçimimiz)
4. **configMap**: Config dosyalarını mount eder
5. **secret**: Secret'ları mount eder
6. **nfs**: Network File System
7. **cloud volumes**: AWS EBS, GCP PD, Azure Disk

**Bizim projede:**
```yaml
# Backup script ConfigMap olarak mount ediliyor
volumes:
- name: backup-script
  configMap:
    name: postgresql-backup-script
    defaultMode: 0755

# Backup storage PVC olarak mount ediliyor
- name: backup-storage
  persistentVolumeClaim:
    claimName: postgresql-backup-pvc
```

---

## Configuration & Secrets

### ConfigMap vs Secret

**S: ConfigMap ve Secret farkı nedir?**

C:

**ConfigMap:**
- Non-sensitive configuration
- Plain text
- Environment variables, config files

**Secret:**
- Sensitive data (passwords, tokens)
- Base64 encoded (encryption değil!)
- etcd'de encrypted at rest (opsiyonel)

**Bizim projede:**
```bash
# Secrets
kubectl get secret
# postgresql-secret  # Passwords
# redis-secret       # Password

# ConfigMaps
kubectl get configmap
# postgresql-backup-script  # Backup shell script
```

### Secret Management

**S: Secret'ları nasıl yönetiyorsunuz?**

C: Bizim projede:

1. **Generation**: Cryptographically secure
```bash
# generate-secret.sh
openssl rand -base64 48 | tr -d '/+=' | head -c 32
```

2. **Storage**: Kubernetes secrets
```bash
kubectl create secret generic postgresql-secret \
    --from-literal=postgres-password="$PASSWORD"
```

3. **Usage**: Environment variables veya volume mount
```yaml
env:
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgresql-secret
      key: postgres-password
```

4. **Access**: Sadece authorized users
```bash
# Credential retrieval script
./scripts/utils/get-credentials.sh postgresql
```

**Production'da:**
- External secret management (Vault, AWS Secrets Manager)
- Secret rotation
- Encryption at rest
- Audit logging

---

## Scheduling & Automation

### CronJob Deep Dive

**S: Backup sisteminiz nasıl çalışıyor?**

C: Kubernetes CronJob kullanıyoruz:

**1. CronJob Definition:**
```yaml
# k8s/backup/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-backup
spec:
  schedule: "0 2 * * *"  # Her gün 2:00 AM
  concurrencyPolicy: Forbid  # Concurrent backup'a izin verme
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            command: ["/bin/sh", "/scripts/backup-postgresql.sh"]
```

**2. Backup Script (ConfigMap):**
```bash
# scripts/backup/backup-postgresql.sh
# 1. pg_dumpall ile SQL dump
# 2. gzip ile compress
# 3. Timestamp ile kaydet
# 4. 7 günden eski backupları sil
```

**3. Storage (PVC):**
```yaml
# k8s/backup/backup-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-backup-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

**Workflow:**
```
2:00 AM → CronJob triggers
       → Job creates Pod
       → Pod mounts backup-script (ConfigMap)
       → Pod mounts backup-storage (PVC)
       → Script runs pg_dumpall
       → Compress with gzip
       → Save to /backups/postgresql/
       → Delete old backups (>7 days)
       → Pod completes
       → Job marked as successful
```

**Avantajları:**
- Kubernetes native (pod restart olsa bile çalışır)
- Monitoring kolay (`kubectl get cronjob`)
- Logs accessible (`kubectl logs`)
- Retry mechanism built-in
- History tutuluyor

### Resource Requests & Limits

**S: Resource requests ve limits nedir?**

C:

**Requests:** "Bu kadar resource garanti et"
**Limits:** "Bundan fazla kullanma"

**Bizim projede:**
```yaml
# PostgreSQL
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"

# Redis
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

**Neden önemli:**
- **Requests**: Scheduler buna göre pod'u node'a yerleştirir
- **Limits**: OOMKilled (Out of Memory) önler
- **QoS Classes**: Guaranteed, Burstable, BestEffort

**QoS Class:**
```bash
kubectl describe pod postgresql-0 | grep "QoS Class"
# QoS Class: Burstable  # requests != limits
```

---

## Project-Specific Questions

### PostgreSQL Deployment

**S: PostgreSQL'i neden StatefulSet ile deploy ettiniz?**

C:
1. **Data Persistence**: Pod restart olsa bile aynı PVC'ye bağlanmalı
2. **Stable Network Identity**: postgresql-0.postgresql.default.svc.cluster.local
3. **Ordered Deployment**: Master-replica setup'ta sıra önemli
4. **Unique Storage**: Her pod'un kendi PVC'si var

**Alternatif:** Deployment kullanabilirdik ama:
- Pod restart olunca farklı PVC'ye bağlanabilir
- Data loss riski
- Master-replica setup zor

### Redis Deployment

**S: Redis'te persistence nasıl sağlanıyor?**

C: İki yöntem:

**1. Kubernetes PVC:**
```yaml
persistence:
  enabled: true
  size: 5Gi
  storageClass: local-path
```

**2. Redis AOF (Append Only File):**
```yaml
commonConfiguration: |-
  appendonly yes
  appendfsync everysec
```

**AOF vs RDB:**
- **RDB**: Snapshot, belirli aralıklarla
- **AOF**: Her write operasyonunu log'lar

**Neden AOF?**
- Data loss minimal (son 1 saniye)
- Crash recovery daha iyi
- Log-based, corrupt olma riski az

### Backup Strategy

**S: Backup restore nasıl yapılır?**

C:

**1. Backup'ı bul:**
```bash
# Backup pod'una gir
kubectl exec -it <backup-pod> -- ls /backups/postgresql/
# postgresql-backup-2024-02-03-020000.sql.gz
```

**2. Backup'ı local'e kopyala:**
```bash
kubectl cp <backup-pod>:/backups/postgresql/backup.sql.gz ./backup.sql.gz
```

**3. Decompress:**
```bash
gunzip backup.sql.gz
```

**4. Restore:**
```bash
psql -h localhost -p 30432 -U postgres < backup.sql
```

**Production'da:**
- Offsite backups (S3, GCS)
- Encryption at rest
- Regular restore tests
- Point-in-time recovery

### Security

**S: Güvenlik önlemleriniz nelerdir?**

C:

**1. Secret Management:**
- Cryptographically secure password generation
- Kubernetes secrets (base64 encoded)
- No hardcoded credentials in git

**2. Network Security:**
- NodePort sadece development için
- Production'da LoadBalancer + Ingress
- Firewall rules (GCP: specific IP ranges)

**3. Access Control:**
- RBAC (Role-Based Access Control) - k3s default
- Service accounts
- Namespace isolation

**4. Data Security:**
- Encryption at rest (PVC)
- Encryption in transit (TLS) - production'da
- Backup encryption - production'da

**Eksiklerimiz (production için):**
- Network policies yok
- Pod security policies yok
- TLS/SSL yok
- Audit logging yok
- Vulnerability scanning yok

### Monitoring & Observability

**S: Monitoring nasıl yapıyorsunuz?**

C: Şu an basic monitoring:

**1. kubectl commands:**
```bash
kubectl get pods -A
kubectl top nodes
kubectl top pods
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

**2. Test scripts:**
```bash
./scripts/test/test-postgresql.sh
./scripts/test/test-redis.sh
```

**Production'da ekleriz:**
- Prometheus + Grafana
- Alertmanager
- Loki (log aggregation)
- Jaeger (distributed tracing)
- Custom metrics (PostgreSQL exporter, Redis exporter)

---

## Quick Reference

### Useful Commands

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes
kubectl get componentstatuses

# Pods
kubectl get pods -A
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- /bin/bash

# Services
kubectl get svc
kubectl describe svc <service-name>
kubectl get endpoints

# Storage
kubectl get pv,pvc
kubectl describe pvc <pvc-name>

# Secrets & ConfigMaps
kubectl get secrets
kubectl get configmaps
kubectl describe secret <secret-name>

# Jobs & CronJobs
kubectl get cronjob
kubectl get jobs
kubectl describe cronjob <cronjob-name>

# Helm
helm list -A
helm status <release-name>
helm history <release-name>
helm rollback <release-name>

# Debugging
kubectl get events --sort-by='.lastTimestamp'
kubectl top nodes
kubectl top pods
```

### Common Issues & Solutions

**Pod CrashLoopBackOff:**
```bash
kubectl logs <pod-name>
kubectl describe pod <pod-name>
# Check: Image, command, resources, secrets
```

**PVC Pending:**
```bash
kubectl describe pvc <pvc-name>
# Check: StorageClass, capacity, access mode
```

**Service not accessible:**
```bash
kubectl get svc
kubectl get endpoints
# Check: Selector labels, port configuration
```

**CronJob not running:**
```bash
kubectl describe cronjob <cronjob-name>
kubectl get jobs
# Check: Schedule, suspend, concurrencyPolicy
```

---

## Interview Tips

### Nasıl Cevap Verilir?

1. **Kısa başla**: "X, Y için kullanılır"
2. **Somut örnek ver**: "Bizim projede..."
3. **Alternatif bahset**: "Production'da şöyle yapardık..."
4. **Trade-off'ları bil**: "Avantajı X, dezavantajı Y"

### Örnek Cevap Yapısı:

**S: Neden NodePort kullandınız?**

**C:** 
"NodePort, cluster dışından service'lere erişim sağlar. Ödev gereksinimi 'external access' istiyordu. 

Bizim projede PostgreSQL 30432, Redis 30379 portlarından erişilebilir. Local VM'de LoadBalancer kullanamayız çünkü cloud provider yok.

Production'da LoadBalancer + Ingress kullanırdık. NodePort'un dezavantajı port range sınırlı (30000-32767) ve her node IP'sini bilmek gerekir. Security için firewall rules ve VPN ekleriz."

### Red Flags (Kaçınılacaklar):

❌ "Bilmiyorum"
✅ "Bu konuda deneyimim yok ama şöyle düşünüyorum..."

❌ "Sadece tutorial'dan yaptım"
✅ "Bitnami chart kullandım çünkü production-ready ve well-maintained"

❌ "Production'da da aynı şekilde yapardım"
✅ "Development için yeterli ama production'da şunları ekleriz..."

---

**Son Not:** Bu döküman interview'a hazırlık için. Her soruyu ezberlemek yerine, kavramları anlamak ve projemizdeki örnekleri bilmek önemli. Interview'da rahat ol, bilmediğin şeyi "bilmiyorum ama öğrenmeye açığım" diyerek geç!
