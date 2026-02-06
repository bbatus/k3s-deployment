#!/bin/bash

#############################################
# setup-backup.sh
# 
# Purpose: Setup PostgreSQL backup system
# Requirements: k3s cluster running, PostgreSQL deployed
# 
# What it does:
#   - Creates backup PVC
#   - Creates ConfigMap with backup script
#   - Creates backup CronJob
#   - Verifies CronJob is scheduled
#   - Displays backup schedule information
#
# Usage: sudo ./setup-backup.sh
#############################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if required files exist
BACKUP_SCRIPT="$SCRIPT_DIR/backup-postgresql.sh"
BACKUP_PVC_YAML="$PROJECT_ROOT/k8s/backup/backup-pvc.yaml"
BACKUP_CRONJOB_YAML="$PROJECT_ROOT/k8s/backup/backup-cronjob.yaml"

if [ ! -f "$BACKUP_SCRIPT" ]; then
    log_error "backup-postgresql.sh not found at $BACKUP_SCRIPT"
    exit 1
fi

if [ ! -f "$BACKUP_PVC_YAML" ]; then
    log_error "backup-pvc.yaml not found at $BACKUP_PVC_YAML"
    exit 1
fi

if [ ! -f "$BACKUP_CRONJOB_YAML" ]; then
    log_error "backup-cronjob.yaml not found at $BACKUP_CRONJOB_YAML"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install k3s first"
    exit 1
fi

log_info "Starting backup system setup..."
echo ""

# Check if PostgreSQL is deployed
log_info "Checking if PostgreSQL is deployed..."

if ! kubectl get deployment postgresql &> /dev/null && ! kubectl get statefulset postgresql &> /dev/null; then
    log_error "PostgreSQL is not deployed"
    log_error "Please deploy PostgreSQL first: ./scripts/install/deploy-services.sh"
    exit 1
fi

log_success "PostgreSQL is deployed"
echo ""

# Create backup PVC
log_info "Creating backup PVC..."

if kubectl get pvc postgresql-backup-pvc &> /dev/null; then
    log_warning "Backup PVC already exists"
else
    if kubectl apply -f "$BACKUP_PVC_YAML" > /dev/null; then
        log_success "Backup PVC created"
    else
        log_error "Failed to create backup PVC"
        exit 1
    fi
fi

# Wait for PVC to be bound
log_info "Waiting for PVC to be bound..."

if kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/postgresql-backup-pvc --timeout=60s > /dev/null 2>&1; then
    log_success "PVC is bound"
else
    log_warning "PVC is not bound yet (this is normal for local-path provisioner)"
fi

echo ""

# Create ConfigMap with backup script
log_info "Creating ConfigMap with backup script..."

if kubectl get configmap postgresql-backup-script &> /dev/null; then
    log_warning "ConfigMap already exists, updating..."
    kubectl create configmap postgresql-backup-script \
        --from-file=backup-postgresql.sh="$BACKUP_SCRIPT" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    log_success "ConfigMap updated"
else
    kubectl create configmap postgresql-backup-script \
        --from-file=backup-postgresql.sh="$BACKUP_SCRIPT" > /dev/null
    log_success "ConfigMap created"
fi

echo ""

# Create backup CronJob
log_info "Creating backup CronJob..."

if kubectl get cronjob postgresql-backup &> /dev/null; then
    log_warning "CronJob already exists, updating..."
    kubectl apply -f "$BACKUP_CRONJOB_YAML" > /dev/null
    log_success "CronJob updated"
else
    kubectl apply -f "$BACKUP_CRONJOB_YAML" > /dev/null
    log_success "CronJob created"
fi

echo ""

# Verify CronJob is scheduled
log_info "Verifying CronJob..."

if kubectl get cronjob postgresql-backup &> /dev/null; then
    log_success "CronJob is scheduled"
    
    # Display CronJob details
    echo ""
    log_info "CronJob details:"
    kubectl get cronjob postgresql-backup
    
    echo ""
    log_info "Schedule: Daily at 2:00 AM UTC"
    log_info "Retention: 7 days"
    log_info "Backup location: /backups/postgresql (inside PVC)"
else
    log_error "CronJob verification failed"
    exit 1
fi

echo ""
log_success "=== Backup System Setup Complete ==="
echo ""

log_info "Backup configuration:"
echo "  Schedule: 0 2 * * * (Daily at 2:00 AM UTC)"
echo "  Retention: 7 days"
echo "  Storage: 20Gi PVC"
echo ""

log_info "To manually trigger a backup:"
echo "  kubectl create job --from=cronjob/postgresql-backup manual-backup-\$(date +%s)"
echo ""

log_info "To view backup jobs:"
echo "  kubectl get jobs -l app=postgresql-backup"
echo ""

log_info "To view backup logs:"
echo "  kubectl logs -l app=postgresql-backup --tail=100"
echo ""

log_info "To list backups:"
echo "  kubectl exec -it \$(kubectl get pod -l app=postgresql-backup -o jsonpath='{.items[0].metadata.name}') -- ls -lh /backups/postgresql/"

exit 0
