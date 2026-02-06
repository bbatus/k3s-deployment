# Local Kubernetes DevOps Infrastructure

Production-ready local Kubernetes infrastructure using k3s, with PostgreSQL and Redis services, automated backups, and comprehensive testing.

## 🎯 Project Overview

This project provides a complete, reproducible Kubernetes infrastructure that can be deployed on a fresh Ubuntu VM with a single command. It includes:

- **k3s Kubernetes Cluster**: Lightweight, production-ready Kubernetes
- **PostgreSQL Database**: Persistent relational database with external access
- **Redis Cache**: High-performance in-memory cache with persistence
- **Automated Backups**: Daily PostgreSQL backups with retention policy
- **Monitoring & Testing**: Connectivity tests and health checks
- **Security**: Kubernetes secrets management, no hardcoded credentials

## 📋 Requirements

### System Requirements
- **OS**: Ubuntu 20.04 or 22.04 LTS
- **CPU**: Minimum 2 cores
- **RAM**: Minimum 4GB
- **Disk**: Minimum 20GB free space
- **Network**: Internet connection for package downloads
- **Access**: Root or sudo privileges

### Pre-installed Software
- Base Ubuntu packages only (bash, apt, coreutils)
- All other dependencies are installed automatically

## 🚀 Quick Start

### One-Command Installation

```bash
# Clone the repository
git clone https://github.com/bbatus/k3s-deployment.git
cd k3s-deployment

# Run the master installation script
sudo ./scripts/install/setup-all.sh
```

That's it! The script will:
1. Install system dependencies (5-10 minutes)
2. Set up k3s cluster
3. Install Helm
4. Deploy PostgreSQL and Redis
5. Configure automated backups

### Verify Installation

```bash
# Test PostgreSQL connectivity
./scripts/test/test-postgresql.sh

# Test Redis connectivity
./scripts/test/test-redis.sh

# Check cluster status
sudo kubectl get nodes
sudo kubectl get pods -A
```

## 📁 Project Structure

```
.
├── README.md                          # This file
├── INTERVIEW_NOTES.md                 # Detailed technical explanations
├── scripts/
│   ├── install/
│   │   ├── setup-all.sh              # Master installation script
│   │   ├── install-dependencies.sh   # System dependencies
│   │   ├── install-k3s.sh            # k3s cluster setup
│   │   ├── install-helm.sh           # Helm installation
│   │   └── deploy-services.sh        # PostgreSQL & Redis deployment
│   ├── backup/
│   │   ├── setup-backup.sh           # Backup system setup
│   │   └── backup-postgresql.sh      # Backup execution script
│   ├── test/
│   │   ├── test-postgresql.sh        # PostgreSQL connectivity tests
│   │   └── test-redis.sh             # Redis connectivity tests
│   └── utils/
│       ├── generate-secret.sh        # Secure password generation
│       └── get-credentials.sh        # Retrieve service credentials
├── helm/
│   └── values/
│       ├── postgresql-values.yaml    # PostgreSQL Helm configuration
│       └── redis-values.yaml         # Redis Helm configuration
├── k8s/
│   └── backup/
│       ├── backup-cronjob.yaml       # Daily backup CronJob
│       └── backup-pvc.yaml           # Backup storage PVC
└── docs/                             # Additional documentation
```

## 🔧 Service Details

### PostgreSQL

**Internal Access** (from within cluster):
```bash
Host: postgresql.default.svc.cluster.local
Port: 5432
Database: postgres
User: postgres
```

**External Access** (from outside cluster):
```bash
Host: localhost (or VM IP address)
Port: 30432
Database: postgres
User: postgres
```

**Connect via psql:**
```bash
# Get password first
./scripts/utils/get-credentials.sh postgresql

# Connect
psql -h localhost -p 30432 -U postgres -d postgres
```

**Features:**
- 10Gi persistent storage
- Automated daily backups (2:00 AM UTC)
- 7-day backup retention
- NodePort external access

### Redis

**Internal Access** (from within cluster):
```bash
Host: redis-master.default.svc.cluster.local
Port: 6379
```

**External Access** (from outside cluster):
```bash
Host: localhost (or VM IP address)
Port: 30379
```

**Connect via redis-cli:**
```bash
# Get password first
./scripts/utils/get-credentials.sh redis

# Connect
redis-cli -h localhost -p 30379 -a <password>
```

**Features:**
- 5Gi persistent storage
- AOF persistence enabled
- 256MB memory limit with LRU eviction
- NodePort external access

## 🔐 Security

### Credentials Management

All passwords are:
- Generated randomly during deployment (32 characters, cryptographically secure)
- Stored in Kubernetes Secrets (base64 encoded, encrypted at rest)
- Never committed to git repository
- Never displayed in plain text in logs

**Retrieve credentials:**
```bash
./scripts/utils/get-credentials.sh postgresql
./scripts/utils/get-credentials.sh redis
```

### Secret Storage

```bash
# Kubernetes secrets
kubectl get secrets
# postgresql-secret: postgres-password, user-password
# redis-secret: redis-password

# View secret (base64 encoded)
kubectl get secret postgresql-secret -o yaml

# Decode secret
kubectl get secret postgresql-secret -o jsonpath='{.data.postgres-password}' | base64 -d
```

## 💾 Backup System

### Automated Backups

- **Schedule**: Daily at 2:00 AM UTC
- **Method**: pg_dumpall (full cluster backup)
- **Compression**: gzip
- **Retention**: 7 days
- **Storage**: 20Gi persistent volume

### Backup Location

```bash
# Inside backup pod
/backups/postgresql/postgresql-backup-YYYY-MM-DD-HHMMSS.sql.gz
```

### Manual Backup

```bash
# Trigger manual backup
kubectl create job --from=cronjob/postgresql-backup manual-backup-$(date +%s)

# Check backup status
kubectl get jobs -l app=postgresql-backup

# View backup logs
kubectl logs -l app=postgresql-backup --tail=100
```

### Restore from Backup

```bash
# 1. Copy backup from pod to local
kubectl cp <backup-pod>:/backups/postgresql/backup.sql.gz ./backup.sql.gz

# 2. Decompress
gunzip backup.sql.gz

# 3. Restore
psql -h localhost -p 30432 -U postgres < backup.sql
```

## 🧪 Testing

### Connectivity Tests

```bash
# Test PostgreSQL (internal + external connections, SQL queries)
./scripts/test/test-postgresql.sh

# Test Redis (internal + external connections, Redis commands)
./scripts/test/test-redis.sh
```

### Manual Testing

```bash
# PostgreSQL
psql -h localhost -p 30432 -U postgres -d postgres -c "SELECT version();"

# Redis
redis-cli -h localhost -p 30379 -a <password> PING
```

### Cluster Health

```bash
# Check nodes
sudo kubectl get nodes

# Check all pods
sudo kubectl get pods -A

# Check services
sudo kubectl get svc

# Check persistent volumes
sudo kubectl get pv,pvc

# Check Helm releases
sudo helm list -A

# Check backup CronJob
sudo kubectl get cronjob
```

## 📚 Useful Commands

### Kubernetes

```bash
# Get cluster info
sudo kubectl cluster-info

# Get pod logs
sudo kubectl logs <pod-name>

# Describe pod (detailed info)
sudo kubectl describe pod <pod-name>

# Execute command in pod
sudo kubectl exec -it <pod-name> -- bash

# Port forward (alternative to NodePort)
sudo kubectl port-forward svc/postgresql 5432:5432
```

### Helm

```bash
# List releases
sudo helm list -A

# Get release values
sudo helm get values postgresql

# Upgrade release
sudo helm upgrade postgresql bitnami/postgresql -f helm/values/postgresql-values.yaml

# Rollback release
sudo helm rollback postgresql

# Uninstall release
sudo helm uninstall postgresql
```

## 🧹 Cleanup

### Complete Infrastructure Removal

To completely remove all infrastructure components (useful for demos or fresh reinstalls):

```bash
# WARNING: This will delete EVERYTHING!
sudo ./scripts/cleanup-all.sh
```

The cleanup script will remove:
- All Helm releases (PostgreSQL, Redis)
- All Kubernetes secrets and PVCs
- k3s cluster completely
- Helm installation
- Configuration files

**Safety Features:**
- Requires explicit "yes" confirmation
- 3-second countdown before execution
- Cannot be undone!

### Partial Cleanup

```bash
# Uninstall only PostgreSQL
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm uninstall postgresql

# Uninstall only Redis
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm uninstall redis

# Delete specific secret
sudo kubectl delete secret postgresql-secret

# Delete specific PVC
sudo kubectl delete pvc data-postgresql-0
```

### Fresh Reinstall

After cleanup, you can reinstall everything:

```bash
# Pull latest changes
git pull

# Run setup again
sudo ./scripts/install/setup-all.sh
```

### Troubleshooting

```bash
# Pod not starting
sudo kubectl describe pod <pod-name>
sudo kubectl logs <pod-name>

# Service not accessible
sudo kubectl get svc
sudo kubectl get endpoints

# Storage issues
sudo kubectl get pv,pvc
sudo kubectl describe pvc <pvc-name>

# k3s issues
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

## 🏗️ Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Ubuntu VM                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                   k3s Cluster                          │  │
│  │                                                         │  │
│  │  ┌──────────────┐         ┌──────────────┐            │  │
│  │  │  PostgreSQL  │         │    Redis     │            │  │
│  │  │     Pod      │         │     Pod      │            │  │
│  │  │              │         │              │            │  │
│  │  │  Port: 5432  │         │  Port: 6379  │            │  │
│  │  └──────┬───────┘         └──────┬───────┘            │  │
│  │         │                        │                     │  │
│  │         │                        │                     │  │
│  │  ┌──────▼───────┐         ┌──────▼───────┐            │  │
│  │  │ PostgreSQL   │         │    Redis     │            │  │
│  │  │     PVC      │         │     PVC      │            │  │
│  │  │   (10Gi)     │         │    (5Gi)     │            │  │
│  │  └──────────────┘         └──────────────┘            │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────┐             │  │
│  │  │      Backup CronJob (Daily)          │             │  │
│  │  │                                       │             │  │
│  │  │  Schedule: 0 2 * * *                 │             │  │
│  │  └──────────────┬───────────────────────┘             │  │
│  │                 │                                      │  │
│  │          ┌──────▼───────┐                             │  │
│  │          │  Backup PVC  │                             │  │
│  │          │   (20Gi)     │                             │  │
│  │          └──────────────┘                             │  │
│  │                                                         │  │
│  │  NodePort Services:                                    │  │
│  │  - PostgreSQL: 30432                                   │  │
│  │  - Redis: 30379                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │
                  External Access
              (psql, redis-cli)
```

### Technology Stack

- **Kubernetes**: k3s (lightweight Kubernetes distribution)
- **Package Manager**: Helm 3
- **Database**: PostgreSQL 15 (Bitnami Helm chart)
- **Cache**: Redis 7 (Bitnami Helm chart)
- **Storage**: local-path provisioner (k3s default)
- **Backup**: pg_dumpall + gzip + Kubernetes CronJob
- **Automation**: Bash scripts

## 🔄 Development Workflow

### Local Development

1. **Write scripts** on your local machine (Mac/Linux)
2. **Commit to git** after each task
3. **Push to GitHub** for version control
4. **Deploy on VM** when ready to test

### Testing on VM

```bash
# On Ubuntu VM
git clone https://github.com/bbatus/k3s-deployment.git
cd k3s-deployment
sudo ./scripts/install/setup-all.sh
```

### Making Changes

```bash
# 1. Make changes locally
vim scripts/install/deploy-services.sh

# 2. Commit changes
git add scripts/install/deploy-services.sh
git commit -m "Update deployment script"
git push

# 3. Pull changes on VM
cd k3s-deployment
git pull

# 4. Re-run affected scripts
sudo ./scripts/install/deploy-services.sh
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is for educational purposes.

## 👤 Author

**Batu Batus**
- GitHub: [@bbatus](https://github.com/bbatus)
- Repository: [k3s-deployment](https://github.com/bbatus/k3s-deployment)

## 📖 Additional Documentation

- [INTERVIEW_NOTES.md](INTERVIEW_NOTES.md) - Detailed technical explanations for each component
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [k3s Documentation](https://docs.k3s.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Redis Documentation](https://redis.io/documentation)

## 🙏 Acknowledgments

- [k3s](https://k3s.io/) - Lightweight Kubernetes
- [Helm](https://helm.sh/) - Kubernetes package manager
- [Bitnami](https://bitnami.com/) - Helm charts for PostgreSQL and Redis
- [PostgreSQL](https://www.postgresql.org/) - Relational database
- [Redis](https://redis.io/) - In-memory data store

---

**Note**: This project is designed for local development and learning purposes. For production deployments, additional security hardening, monitoring, and high availability configurations are recommended.
