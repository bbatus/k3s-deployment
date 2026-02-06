#!/bin/bash

#############################################
# cleanup-all.sh
# 
# Purpose: Complete cleanup of k3s infrastructure
# WARNING: This will DELETE everything!
# 
# What it does:
#   - Uninstalls Helm releases (PostgreSQL, Redis)
#   - Deletes Kubernetes secrets
#   - Deletes PVCs and PVs
#   - Uninstalls k3s cluster completely
#   - Removes Helm
#   - Cleans up configuration files
#
# Usage: sudo ./cleanup-all.sh
#############################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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

log_header() {
    echo ""
    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

clear

log_header "Complete Infrastructure Cleanup"

log_warning "⚠️  WARNING: This will DELETE everything! ⚠️"
echo ""
log_info "This script will remove:"
echo "  ✗ All Helm releases (PostgreSQL, Redis)"
echo "  ✗ All Kubernetes secrets"
echo "  ✗ All PersistentVolumeClaims and data"
echo "  ✗ k3s cluster completely"
echo "  ✗ Helm installation"
echo "  ✗ Configuration files"
echo ""
log_warning "This action CANNOT be undone!"
echo ""

# Confirmation
read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_warning "Starting cleanup in 3 seconds... Press Ctrl+C to cancel"
sleep 3

START_TIME=$(date +%s)

#############################################
# Step 1: Uninstall Helm Releases
#############################################

log_header "Step 1/5: Uninstalling Helm Releases"

if command -v helm &> /dev/null && [ -f /etc/rancher/k3s/k3s.yaml ]; then
    log_info "Checking for Helm releases..."
    
    # Uninstall Redis
    if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list -n default | grep -q "^redis"; then
        log_info "Uninstalling Redis..."
        if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm uninstall redis -n default > /dev/null 2>&1; then
            log_success "Redis uninstalled"
        else
            log_warning "Failed to uninstall Redis (may not exist)"
        fi
    else
        log_info "Redis not found, skipping..."
    fi
    
    # Uninstall PostgreSQL
    if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list -n default | grep -q "^postgresql"; then
        log_info "Uninstalling PostgreSQL..."
        if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm uninstall postgresql -n default > /dev/null 2>&1; then
            log_success "PostgreSQL uninstalled"
        else
            log_warning "Failed to uninstall PostgreSQL (may not exist)"
        fi
    else
        log_info "PostgreSQL not found, skipping..."
    fi
    
    log_success "Helm releases cleaned up"
else
    log_info "Helm or k3s not found, skipping Helm cleanup..."
fi

echo ""

#############################################
# Step 2: Delete Kubernetes Resources
#############################################

log_header "Step 2/5: Deleting Kubernetes Resources"

if command -v kubectl &> /dev/null && [ -f /etc/rancher/k3s/k3s.yaml ]; then
    log_info "Deleting secrets..."
    
    # Delete secrets
    kubectl delete secret postgresql-secret --ignore-not-found=true > /dev/null 2>&1 || true
    kubectl delete secret redis-secret --ignore-not-found=true > /dev/null 2>&1 || true
    
    log_success "Secrets deleted"
    
    log_info "Deleting PVCs..."
    
    # Delete all PVCs in default namespace
    kubectl delete pvc --all -n default --timeout=60s > /dev/null 2>&1 || true
    
    log_success "PVCs deleted"
    
    log_info "Deleting backup resources..."
    
    # Delete backup CronJob and PVC
    kubectl delete cronjob postgresql-backup --ignore-not-found=true > /dev/null 2>&1 || true
    kubectl delete pvc postgresql-backup-pvc --ignore-not-found=true > /dev/null 2>&1 || true
    kubectl delete configmap postgresql-backup-script --ignore-not-found=true > /dev/null 2>&1 || true
    
    log_success "Backup resources deleted"
else
    log_info "kubectl not found, skipping Kubernetes cleanup..."
fi

echo ""

#############################################
# Step 3: Uninstall k3s
#############################################

log_header "Step 3/5: Uninstalling k3s Cluster"

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    log_info "Uninstalling k3s..."
    log_info "This may take a minute..."
    
    if /usr/local/bin/k3s-uninstall.sh > /dev/null 2>&1; then
        log_success "k3s uninstalled successfully"
    else
        log_warning "k3s uninstall script failed (may already be uninstalled)"
    fi
else
    log_info "k3s not installed, skipping..."
fi

echo ""

#############################################
# Step 4: Uninstall Helm
#############################################

log_header "Step 4/5: Uninstalling Helm"

if command -v helm &> /dev/null; then
    log_info "Removing Helm..."
    
    # Remove Helm binary
    rm -f /usr/local/bin/helm
    
    # Remove Helm cache and config
    rm -rf /root/.cache/helm
    rm -rf /root/.config/helm
    rm -rf /root/.local/share/helm
    
    # Remove Helm cache for regular user if exists
    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
        rm -rf "$USER_HOME/.cache/helm"
        rm -rf "$USER_HOME/.config/helm"
        rm -rf "$USER_HOME/.local/share/helm"
    fi
    
    log_success "Helm removed"
else
    log_info "Helm not installed, skipping..."
fi

echo ""

#############################################
# Step 5: Clean Configuration Files
#############################################

log_header "Step 5/5: Cleaning Configuration Files"

log_info "Removing kubeconfig files..."

# Remove kubeconfig for root
rm -f /root/.kube/config
rm -rf /root/.kube

# Remove kubeconfig for regular user
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    rm -f "$USER_HOME/.kube/config"
    # Don't remove .kube directory as user might have other configs
fi

log_success "Configuration files cleaned"

# Remove k3s data directory (if exists)
if [ -d /var/lib/rancher ]; then
    log_info "Removing k3s data directory..."
    rm -rf /var/lib/rancher
    log_success "k3s data directory removed"
fi

echo ""

#############################################
# Cleanup Complete
#############################################

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_header "Cleanup Complete!"

log_success "All infrastructure components have been removed"
echo ""
log_info "Cleanup completed in ${DURATION} seconds"
echo ""

log_info "System is now clean. You can run setup-all.sh to reinstall:"
echo "  sudo ./scripts/install/setup-all.sh"
echo ""

log_info "Removed components:"
echo "  ✗ PostgreSQL and Redis (Helm releases)"
echo "  ✗ All Kubernetes secrets and PVCs"
echo "  ✗ k3s cluster"
echo "  ✗ Helm"
echo "  ✗ Configuration files"
echo ""

log_warning "Note: System packages (curl, git, psql, redis-cli) were NOT removed"
log_info "To remove them: sudo apt-get remove postgresql-client redis-tools"

exit 0
