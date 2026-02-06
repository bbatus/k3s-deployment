#!/bin/bash

#############################################
# install-k3s.sh
# 
# Purpose: Install and configure k3s Kubernetes cluster
# Requirements: Ubuntu 20.04 or 22.04, sudo access, curl installed
# 
# What it does:
#   - Downloads and installs k3s
#   - Configures k3s to start on boot (systemd)
#   - Waits for cluster to be ready
#   - Configures kubeconfig for root and regular users
#   - Verifies cluster accessibility
#
# Usage: sudo ./install-k3s.sh
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

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    log_error "curl is not installed. Please run install-dependencies.sh first"
    exit 1
fi

log_info "Starting k3s installation..."
echo ""

# Check if k3s is already installed
if command -v k3s &> /dev/null; then
    log_warning "k3s is already installed"
    K3S_VERSION=$(k3s --version | head -n1 | awk '{print $3}')
    log_info "Current version: $K3S_VERSION"
    
    # Check if k3s service is running
    if systemctl is-active --quiet k3s; then
        log_success "k3s service is already running"
    else
        log_info "Starting k3s service..."
        systemctl start k3s
        log_success "k3s service started"
    fi
else
    # Download and install k3s
    log_info "Downloading k3s installation script..."
    
    if curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh; then
        log_success "k3s installation script downloaded"
    else
        log_error "Failed to download k3s installation script"
        exit 1
    fi
    
    log_info "Installing k3s..."
    log_info "This may take a few minutes..."
    
    # Install k3s with specific options
    # INSTALL_K3S_EXEC: Additional k3s server arguments
    if sh /tmp/k3s-install.sh; then
        log_success "k3s installed successfully"
        rm -f /tmp/k3s-install.sh
    else
        log_error "Failed to install k3s"
        rm -f /tmp/k3s-install.sh
        exit 1
    fi
fi

echo ""
log_info "Configuring k3s to start on boot..."

# Enable k3s service
if systemctl enable k3s &> /dev/null; then
    log_success "k3s service enabled (will start on boot)"
else
    log_warning "Failed to enable k3s service"
fi

echo ""
log_info "Waiting for k3s cluster to be ready..."

# Wait for k3s to be ready (max 60 seconds)
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if k3s kubectl get nodes &> /dev/null; then
        log_success "k3s cluster is ready!"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    echo -n "."
done

echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_error "Timeout waiting for k3s cluster to be ready"
    exit 1
fi

echo ""
log_info "Configuring kubeconfig..."

# Configure kubeconfig for root user
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
log_success "Kubeconfig configured for root user"

# Configure kubeconfig for regular users (if SUDO_USER is set)
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    KUBE_DIR="$USER_HOME/.kube"
    
    log_info "Configuring kubeconfig for user: $SUDO_USER"
    
    # Create .kube directory
    mkdir -p "$KUBE_DIR"
    
    # Copy kubeconfig
    cp /etc/rancher/k3s/k3s.yaml "$KUBE_DIR/config"
    
    # Set ownership
    chown -R "$SUDO_USER:$SUDO_USER" "$KUBE_DIR"
    chmod 600 "$KUBE_DIR/config"
    
    log_success "Kubeconfig configured for $SUDO_USER"
    log_info "User $SUDO_USER can now use kubectl without sudo"
fi

echo ""
log_info "Verifying cluster accessibility..."

# Verify cluster is accessible
if k3s kubectl get nodes &> /dev/null; then
    log_success "Cluster is accessible"
    echo ""
    log_info "Cluster information:"
    k3s kubectl get nodes
    echo ""
    k3s kubectl version --short 2>/dev/null || k3s kubectl version
else
    log_error "Failed to access cluster"
    exit 1
fi

echo ""
log_success "k3s installation completed successfully!"
echo ""
log_info "Next steps:"
echo "  1. Install Helm: ./scripts/install/install-helm.sh"
echo "  2. Deploy services: ./scripts/install/deploy-services.sh"
echo ""
log_info "Useful commands:"
echo "  - Check cluster status: sudo k3s kubectl get nodes"
echo "  - Check pods: sudo k3s kubectl get pods -A"
echo "  - Check services: sudo k3s kubectl get svc -A"

exit 0
