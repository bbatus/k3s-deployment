#!/bin/bash

#############################################
# deploy-services.sh
# 
# Purpose: Deploy PostgreSQL and Redis services using Helm
# Requirements: k3s cluster running, Helm installed
# 
# What it does:
#   - Generates random passwords for PostgreSQL and Redis
#   - Creates Kubernetes secrets
#   - Deploys PostgreSQL using Helm with custom values
#   - Deploys Redis using Helm with custom values
#   - Waits for pods to be ready
#   - Displays connection information
#
# Usage: sudo ./deploy-services.sh
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
GENERATE_SECRET_SCRIPT="$PROJECT_ROOT/scripts/utils/generate-secret.sh"
POSTGRESQL_VALUES="$PROJECT_ROOT/helm/values/postgresql-values.yaml"
REDIS_VALUES="$PROJECT_ROOT/helm/values/redis-values.yaml"

if [ ! -f "$GENERATE_SECRET_SCRIPT" ]; then
    log_error "generate-secret.sh not found at $GENERATE_SECRET_SCRIPT"
    exit 1
fi

if [ ! -f "$POSTGRESQL_VALUES" ]; then
    log_error "postgresql-values.yaml not found at $POSTGRESQL_VALUES"
    exit 1
fi

if [ ! -f "$REDIS_VALUES" ]; then
    log_error "redis-values.yaml not found at $REDIS_VALUES"
    exit 1
fi

# Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install k3s first"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    log_error "helm not found. Please install Helm first"
    exit 1
fi

log_info "Starting service deployment..."
echo ""

#############################################
# PostgreSQL Deployment
#############################################

log_info "=== Deploying PostgreSQL ==="
echo ""

# Check if PostgreSQL is already deployed
if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list -n default | grep -q "^postgresql"; then
    log_warning "PostgreSQL is already deployed"
    log_info "To redeploy, first run: helm uninstall postgresql"
else
    # Generate passwords
    log_info "Generating PostgreSQL passwords..."
    POSTGRES_PASSWORD=$("$GENERATE_SECRET_SCRIPT" 32)
    USER_PASSWORD=$("$GENERATE_SECRET_SCRIPT" 32)
    
    if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$USER_PASSWORD" ]; then
        log_error "Failed to generate passwords"
        exit 1
    fi
    
    log_success "Passwords generated"
    
    # Create Kubernetes secret
    log_info "Creating PostgreSQL secret..."
    
    kubectl create secret generic postgresql-secret \
        --from-literal=postgres-password="$POSTGRES_PASSWORD" \
        --from-literal=user-password="$USER_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    log_success "PostgreSQL secret created"
    
    # Deploy PostgreSQL using Helm
    log_info "Deploying PostgreSQL with Helm..."
    log_info "This may take a few minutes..."
    
    if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install postgresql bitnami/postgresql \
        -f "$POSTGRESQL_VALUES" \
        --namespace default \
        --wait \
        --timeout 5m > /dev/null 2>&1; then
        log_success "PostgreSQL deployed successfully"
    else
        log_error "Failed to deploy PostgreSQL"
        log_info "Check logs with: kubectl logs -l app.kubernetes.io/name=postgresql"
        exit 1
    fi
    
    # Wait for PostgreSQL pod to be ready
    log_info "Waiting for PostgreSQL pod to be ready..."
    
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=postgresql \
        --timeout=300s > /dev/null 2>&1; then
        log_success "PostgreSQL pod is ready"
    else
        log_error "Timeout waiting for PostgreSQL pod"
        exit 1
    fi
fi

echo ""

#############################################
# Redis Deployment
#############################################

log_info "=== Deploying Redis ==="
echo ""

# Check if Redis is already deployed
if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list -n default | grep -q "^redis"; then
    log_warning "Redis is already deployed"
    log_info "To redeploy, first run: helm uninstall redis"
else
    # Generate password
    log_info "Generating Redis password..."
    REDIS_PASSWORD=$("$GENERATE_SECRET_SCRIPT" 32)
    
    if [ -z "$REDIS_PASSWORD" ]; then
        log_error "Failed to generate password"
        exit 1
    fi
    
    log_success "Password generated"
    
    # Create Kubernetes secret
    log_info "Creating Redis secret..."
    
    kubectl create secret generic redis-secret \
        --from-literal=redis-password="$REDIS_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    log_success "Redis secret created"
    
    # Deploy Redis using Helm
    log_info "Deploying Redis with Helm..."
    log_info "This may take a few minutes..."
    
    if KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install redis bitnami/redis \
        -f "$REDIS_VALUES" \
        --namespace default \
        --wait \
        --timeout 5m > /dev/null 2>&1; then
        log_success "Redis deployed successfully"
    else
        log_error "Failed to deploy Redis"
        log_info "Check logs with: kubectl logs -l app.kubernetes.io/name=redis"
        exit 1
    fi
    
    # Wait for Redis pod to be ready
    log_info "Waiting for Redis pod to be ready..."
    
    if kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=redis \
        --timeout=300s > /dev/null 2>&1; then
        log_success "Redis pod is ready"
    else
        log_error "Timeout waiting for Redis pod"
        exit 1
    fi
fi

echo ""

#############################################
# Display Connection Information
#############################################

log_success "=== Deployment Complete ==="
echo ""
log_info "Services deployed successfully!"
echo ""

log_info "PostgreSQL Connection:"
echo "  Internal: postgresql.default.svc.cluster.local:5432"
echo "  External: localhost:30432 (or VM IP:30432)"
echo "  Database: postgres"
echo "  User: postgres"
echo ""

log_info "Redis Connection:"
echo "  Internal: redis-master.default.svc.cluster.local:6379"
echo "  External: localhost:30379 (or VM IP:30379)"
echo ""

log_info "To retrieve credentials:"
echo "  PostgreSQL: ./scripts/utils/get-credentials.sh postgresql"
echo "  Redis: ./scripts/utils/get-credentials.sh redis"
echo ""

log_info "To test connectivity:"
echo "  PostgreSQL: ./scripts/test/test-postgresql.sh"
echo "  Redis: ./scripts/test/test-redis.sh"
echo ""

log_info "To check pod status:"
echo "  kubectl get pods -l app.kubernetes.io/name=postgresql"
echo "  kubectl get pods -l app.kubernetes.io/name=redis"
echo ""

log_info "To check services:"
echo "  kubectl get svc"

exit 0
