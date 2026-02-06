#!/bin/bash

#############################################
# setup-all.sh
# 
# Purpose: Master installation script - sets up complete k3s infrastructure
# Requirements: Ubuntu 20.04 or 22.04, sudo access, internet connection
# 
# What it does:
#   1. Installs system dependencies
#   2. Installs k3s Kubernetes cluster
#   3. Installs Helm package manager
#   4. Deploys PostgreSQL and Redis services
#   5. Sets up backup system
#   6. Displays summary and next steps
#
# Usage: sudo ./setup-all.sh
#############################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${MAGENTA}[STEP $1]${NC} $2"
}

log_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Track start time
START_TIME=$(date +%s)

# Display banner
clear
log_header "Local Kubernetes DevOps Infrastructure Setup"

log_info "This script will set up a complete k3s infrastructure with:"
echo "  ✓ System dependencies (curl, git, openssl, psql, redis-cli)"
echo "  ✓ k3s Kubernetes cluster"
echo "  ✓ Helm package manager"
echo "  ✓ PostgreSQL database (with persistence and external access)"
echo "  ✓ Redis cache (with persistence and external access)"
echo "  ✓ Automated backup system (daily PostgreSQL backups)"
echo ""
log_warning "This process may take 5-10 minutes depending on your internet connection."
echo ""

# Confirmation prompt
read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation cancelled by user"
    exit 0
fi

echo ""

#############################################
# Step 1: Install Dependencies
#############################################

log_header "Step 1/5: Installing System Dependencies"

log_step "1" "Running install-dependencies.sh..."

if [ -f "$SCRIPT_DIR/install-dependencies.sh" ]; then
    if bash "$SCRIPT_DIR/install-dependencies.sh"; then
        log_success "System dependencies installed successfully"
    else
        log_error "Failed to install system dependencies"
        exit 1
    fi
else
    log_error "install-dependencies.sh not found at $SCRIPT_DIR"
    exit 1
fi

echo ""

#############################################
# Step 2: Install k3s
#############################################

log_header "Step 2/5: Installing k3s Kubernetes Cluster"

log_step "2" "Running install-k3s.sh..."

if [ -f "$SCRIPT_DIR/install-k3s.sh" ]; then
    if bash "$SCRIPT_DIR/install-k3s.sh"; then
        log_success "k3s cluster installed successfully"
    else
        log_error "Failed to install k3s cluster"
        exit 1
    fi
else
    log_error "install-k3s.sh not found at $SCRIPT_DIR"
    exit 1
fi

echo ""

#############################################
# Step 3: Install Helm
#############################################

log_header "Step 3/5: Installing Helm Package Manager"

log_step "3" "Running install-helm.sh..."

if [ -f "$SCRIPT_DIR/install-helm.sh" ]; then
    if bash "$SCRIPT_DIR/install-helm.sh"; then
        log_success "Helm installed successfully"
    else
        log_error "Failed to install Helm"
        exit 1
    fi
else
    log_error "install-helm.sh not found at $SCRIPT_DIR"
    exit 1
fi

echo ""

#############################################
# Step 4: Deploy Services
#############################################

log_header "Step 4/5: Deploying PostgreSQL and Redis"

log_step "4" "Running deploy-services.sh..."

if [ -f "$SCRIPT_DIR/deploy-services.sh" ]; then
    if bash "$SCRIPT_DIR/deploy-services.sh"; then
        log_success "Services deployed successfully"
    else
        log_error "Failed to deploy services"
        exit 1
    fi
else
    log_error "deploy-services.sh not found at $SCRIPT_DIR"
    exit 1
fi

echo ""

#############################################
# Step 5: Setup Backup System
#############################################

log_header "Step 5/5: Setting Up Backup System"

log_step "5" "Running setup-backup.sh..."

BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backup/setup-backup.sh"

if [ -f "$BACKUP_SCRIPT" ]; then
    if bash "$BACKUP_SCRIPT"; then
        log_success "Backup system configured successfully"
    else
        log_error "Failed to setup backup system"
        exit 1
    fi
else
    log_error "setup-backup.sh not found at $BACKUP_SCRIPT"
    exit 1
fi

echo ""

#############################################
# Installation Complete
#############################################

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log_header "Installation Complete! 🎉"

log_success "All components installed successfully in ${MINUTES}m ${SECONDS}s"
echo ""

log_info "Installed Components:"
echo "  ✓ System dependencies (curl, git, openssl, psql, redis-cli)"
echo "  ✓ k3s Kubernetes cluster"
echo "  ✓ Helm package manager (with Bitnami repository)"
echo "  ✓ PostgreSQL database (with 10Gi persistent storage)"
echo "  ✓ Redis cache (with 5Gi persistent storage)"
echo "  ✓ Automated backup system (daily at 2:00 AM)"
echo ""

log_info "Service Endpoints:"
echo ""
echo "  PostgreSQL:"
echo "    Internal: postgresql.default.svc.cluster.local:5432"
echo "    External: localhost:30432 (or VM IP:30432)"
echo "    Database: postgres"
echo "    User: postgres"
echo ""
echo "  Redis:"
echo "    Internal: redis-master.default.svc.cluster.local:6379"
echo "    External: localhost:30379 (or VM IP:30379)"
echo ""

log_info "Useful Commands:"
echo ""
echo "  # Get credentials"
echo "  ./scripts/utils/get-credentials.sh postgresql"
echo "  ./scripts/utils/get-credentials.sh redis"
echo ""
echo "  # Test connectivity"
echo "  ./scripts/test/test-postgresql.sh"
echo "  ./scripts/test/test-redis.sh"
echo ""
echo "  # Check cluster status"
echo "  sudo kubectl get nodes"
echo "  sudo kubectl get pods -A"
echo "  sudo kubectl get svc"
echo ""
echo "  # Check Helm releases"
echo "  sudo helm list -A"
echo ""
echo "  # View backup jobs"
echo "  sudo kubectl get cronjob"
echo "  sudo kubectl get jobs -l app=postgresql-backup"
echo ""

log_info "Next Steps:"
echo ""
echo "  1. Test PostgreSQL connectivity:"
echo "     ./scripts/test/test-postgresql.sh"
echo ""
echo "  2. Test Redis connectivity:"
echo "     ./scripts/test/test-redis.sh"
echo ""
echo "  3. Get service credentials:"
echo "     ./scripts/utils/get-credentials.sh postgresql"
echo "     ./scripts/utils/get-credentials.sh redis"
echo ""
echo "  4. Connect to PostgreSQL:"
echo "     psql -h localhost -p 30432 -U postgres -d postgres"
echo ""
echo "  5. Connect to Redis:"
echo "     redis-cli -h localhost -p 30379 -a <password>"
echo ""

log_warning "Important Notes:"
echo "  - Credentials are stored in Kubernetes secrets"
echo "  - Backups run daily at 2:00 AM UTC"
echo "  - Backups are retained for 7 days"
echo "  - All data is persisted in local-path storage"
echo ""

log_success "Setup complete! Your local Kubernetes infrastructure is ready to use."
echo ""

exit 0
