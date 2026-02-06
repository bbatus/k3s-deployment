#!/bin/bash

#############################################
# install-dependencies.sh
# 
# Purpose: Install system-level dependencies required for k3s cluster
# Requirements: Ubuntu 20.04 or 22.04, sudo access
# 
# Installs:
#   - curl: For downloading installation scripts
#   - git: For version control
#   - openssl: For password generation
#   - postgresql-client: For PostgreSQL connectivity tests
#   - redis-tools: For Redis connectivity tests
#
# Usage: sudo ./install-dependencies.sh
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

log_info "Starting dependency installation..."
echo ""

# Update package lists
log_info "Updating package lists..."
if apt-get update -qq; then
    log_success "Package lists updated"
else
    log_error "Failed to update package lists"
    exit 1
fi

echo ""

# Function to check if package is installed
is_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Function to install package with idempotency check
install_package() {
    local package=$1
    local description=$2
    
    if is_installed "$package"; then
        log_warning "$description is already installed, skipping..."
        return 0
    fi
    
    log_info "Installing $description..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$package" > /dev/null 2>&1; then
        log_success "$description installed successfully"
        return 0
    else
        log_error "Failed to install $description"
        return 1
    fi
}

# Function to verify installation
verify_command() {
    local command=$1
    local package=$2
    
    if command -v "$command" &> /dev/null; then
        local version
        case "$command" in
            git)
                version=$(git --version 2>/dev/null | awk '{print $3}')
                ;;
            curl)
                version=$(curl --version 2>/dev/null | head -n1 | awk '{print $2}')
                ;;
            openssl)
                version=$(openssl version 2>/dev/null | awk '{print $2}')
                ;;
            psql)
                version=$(psql --version 2>/dev/null | awk '{print $3}')
                ;;
            redis-cli)
                version=$(redis-cli --version 2>/dev/null | awk '{print $2}')
                ;;
            *)
                version="installed"
                ;;
        esac
        log_success "$command verified (version: $version)"
        return 0
    else
        log_error "$command not found after installing $package"
        return 1
    fi
}

# Install packages
echo "Installing required packages..."
echo ""

install_package "curl" "curl"
install_package "git" "git"
install_package "openssl" "openssl"
install_package "postgresql-client" "PostgreSQL client"
install_package "redis-tools" "Redis tools"

echo ""
log_info "Verifying installations..."
echo ""

# Verify all installations
VERIFICATION_FAILED=0

verify_command "curl" "curl" || VERIFICATION_FAILED=1
verify_command "git" "git" || VERIFICATION_FAILED=1
verify_command "openssl" "openssl" || VERIFICATION_FAILED=1
verify_command "psql" "postgresql-client" || VERIFICATION_FAILED=1
verify_command "redis-cli" "redis-tools" || VERIFICATION_FAILED=1

echo ""

if [ $VERIFICATION_FAILED -eq 0 ]; then
    log_success "All dependencies installed and verified successfully!"
    echo ""
    log_info "Installed components:"
    echo "  ✓ curl"
    echo "  ✓ git"
    echo "  ✓ openssl"
    echo "  ✓ postgresql-client (psql)"
    echo "  ✓ redis-tools (redis-cli)"
    exit 0
else
    log_error "Some verifications failed. Please check the errors above."
    exit 1
fi
