#!/bin/bash

#############################################
# install-helm.sh
# 
# Purpose: Install Helm package manager for Kubernetes
# Requirements: curl installed, k3s cluster running
# 
# What it does:
#   - Downloads and installs Helm binary
#   - Verifies Helm installation
#   - Adds Bitnami Helm repository
#   - Updates Helm repositories
#
# Usage: sudo ./install-helm.sh
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

log_info "Starting Helm installation..."
echo ""

# Check if Helm is already installed
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null | awk '{print $1}' || helm version --template='{{.Version}}' 2>/dev/null)
    log_warning "Helm is already installed (version: $HELM_VERSION)"
    log_info "Skipping installation..."
else
    # Download Helm installation script
    log_info "Downloading Helm installation script..."
    
    if curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh; then
        log_success "Helm installation script downloaded"
    else
        log_error "Failed to download Helm installation script"
        exit 1
    fi
    
    # Make script executable
    chmod 700 /tmp/get-helm.sh
    
    # Install Helm
    log_info "Installing Helm..."
    
    if /tmp/get-helm.sh; then
        log_success "Helm installed successfully"
        rm -f /tmp/get-helm.sh
    else
        log_error "Failed to install Helm"
        rm -f /tmp/get-helm.sh
        exit 1
    fi
fi

echo ""
log_info "Verifying Helm installation..."

# Verify Helm is accessible
if command -v helm &> /dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null | awk '{print $1}' || helm version --template='{{.Version}}' 2>/dev/null)
    log_success "Helm verified (version: $HELM_VERSION)"
else
    log_error "Helm command not found after installation"
    exit 1
fi

echo ""
log_info "Configuring Helm repositories..."

# Set kubeconfig for Helm
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Add Bitnami repository
log_info "Adding Bitnami Helm repository..."

if helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null; then
    log_success "Bitnami repository added"
elif helm repo list 2>/dev/null | grep -q "bitnami"; then
    log_warning "Bitnami repository already exists"
else
    log_error "Failed to add Bitnami repository"
    exit 1
fi

# Update Helm repositories
log_info "Updating Helm repositories..."

if helm repo update > /dev/null 2>&1; then
    log_success "Helm repositories updated"
else
    log_error "Failed to update Helm repositories"
    exit 1
fi

echo ""
log_info "Listing configured repositories..."
helm repo list

echo ""
log_success "Helm installation completed successfully!"
echo ""
log_info "Next steps:"
echo "  1. Deploy services: ./scripts/install/deploy-services.sh"
echo ""
log_info "Useful commands:"
echo "  - Search charts: helm search repo <keyword>"
echo "  - List installed releases: helm list -A"
echo "  - Show chart info: helm show chart bitnami/<chart-name>"

exit 0
