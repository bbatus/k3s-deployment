#!/bin/bash

#############################################
# test-redis.sh
# 
# Purpose: Test Redis connectivity (internal and external)
# Requirements: Redis deployed, redis-cli installed
# 
# What it does:
#   - Retrieves Redis credentials
#   - Tests internal cluster connection (cluster DNS)
#   - Tests external connection (NodePort)
#   - Executes sample Redis commands (SET/GET)
#   - Displays success or error messages
#
# Usage: ./test-redis.sh
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

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if redis-cli is installed
if ! command -v redis-cli &> /dev/null; then
    log_error "redis-cli not found"
    log_error "Please install it: sudo apt-get install redis-tools"
    exit 1
fi

log_info "=== Redis Connectivity Test ==="
echo ""

# Retrieve Redis credentials
log_info "Retrieving Redis credentials..."

# Try kubectl first (if available)
if command -v kubectl &> /dev/null; then
    REDIS_PASSWORD=$(kubectl get secret redis-secret -o jsonpath='{.data.redis-password}' 2>/dev/null | base64 -d 2>/dev/null)
else
    log_error "kubectl not found. Cannot retrieve credentials."
    exit 1
fi

if [ -z "$REDIS_PASSWORD" ]; then
    log_error "Failed to retrieve Redis password"
    log_error "Make sure Redis is deployed: ./scripts/install/deploy-services.sh"
    exit 1
fi

log_success "Credentials retrieved"
echo ""

# Test 1: Internal Connection (Cluster DNS)
log_info "Test 1: Internal Connection (Cluster DNS)"
log_info "Connecting to: redis-master.default.svc.cluster.local:6379"

INTERNAL_HOST="redis-master.default.svc.cluster.local"
INTERNAL_PORT="6379"

if redis-cli -h "$INTERNAL_HOST" -p "$INTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning PING > /dev/null 2>&1; then
    log_success "Internal connection successful"
    
    # Get Redis info
    REDIS_VERSION=$(redis-cli -h "$INTERNAL_HOST" -p "$INTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning INFO server 2>/dev/null | grep "redis_version" | cut -d: -f2 | tr -d '\r')
    echo "  Version: Redis $REDIS_VERSION"
else
    log_error "Internal connection failed"
    log_warning "This is expected if running outside the Kubernetes cluster"
fi

echo ""

# Test 2: External Connection (NodePort)
log_info "Test 2: External Connection (NodePort)"
log_info "Connecting to: localhost:30379"

EXTERNAL_HOST="localhost"
EXTERNAL_PORT="30379"

if redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning PING > /dev/null 2>&1; then
    log_success "External connection successful"
    
    # Get PING response
    PING_RESPONSE=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning PING 2>/dev/null)
    echo "  Response: $PING_RESPONSE"
else
    log_error "External connection failed"
    log_error "Possible reasons:"
    echo "  - Redis pod is not running"
    echo "  - NodePort service is not configured"
    echo "  - Firewall blocking port 30379"
    echo "  - Incorrect password"
    echo ""
    log_info "Check pod status: kubectl get pods -l app.kubernetes.io/name=redis"
    log_info "Check service: kubectl get svc redis-master"
    exit 1
fi

echo ""

# Test 3: Redis Operations
log_info "Test 3: Redis Operations"

# Generate unique test key
TEST_KEY="connectivity_test_$(date +%s)"
TEST_VALUE="Redis connectivity test at $(date '+%Y-%m-%d %H:%M:%S')"

# SET operation
log_info "Testing SET operation..."

if redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning SET "$TEST_KEY" "$TEST_VALUE" > /dev/null 2>&1; then
    log_success "SET operation successful"
    echo "  Key: $TEST_KEY"
else
    log_error "SET operation failed"
    exit 1
fi

# GET operation
log_info "Testing GET operation..."

RETRIEVED_VALUE=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning GET "$TEST_KEY" 2>/dev/null)

if [ $? -eq 0 ] && [ "$RETRIEVED_VALUE" = "$TEST_VALUE" ]; then
    log_success "GET operation successful"
    echo "  Value: $RETRIEVED_VALUE"
else
    log_error "GET operation failed or value mismatch"
    exit 1
fi

# EXISTS operation
log_info "Testing EXISTS operation..."

EXISTS_RESULT=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning EXISTS "$TEST_KEY" 2>/dev/null)

if [ "$EXISTS_RESULT" = "1" ]; then
    log_success "EXISTS operation successful"
    echo "  Key exists: true"
else
    log_error "EXISTS operation failed"
    exit 1
fi

# EXPIRE operation
log_info "Testing EXPIRE operation..."

if redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning EXPIRE "$TEST_KEY" 60 > /dev/null 2>&1; then
    log_success "EXPIRE operation successful"
    echo "  TTL: 60 seconds"
    
    # Get TTL
    TTL=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning TTL "$TEST_KEY" 2>/dev/null)
    echo "  Remaining TTL: $TTL seconds"
else
    log_error "EXPIRE operation failed"
    exit 1
fi

# DEL operation (cleanup)
log_info "Testing DEL operation (cleanup)..."

if redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning DEL "$TEST_KEY" > /dev/null 2>&1; then
    log_success "DEL operation successful"
    echo "  Test key deleted"
else
    log_warning "DEL operation failed (not critical)"
fi

echo ""

# Test 4: Redis Info
log_info "Test 4: Redis Server Info"

# Get memory info
USED_MEMORY=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
MAXMEMORY=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning CONFIG GET maxmemory 2>/dev/null | tail -n1)

log_info "Memory Usage:"
echo "  Used Memory: $USED_MEMORY"
echo "  Max Memory: $MAXMEMORY bytes"

# Get connected clients
CONNECTED_CLIENTS=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning INFO clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
echo "  Connected Clients: $CONNECTED_CLIENTS"

# Get total keys
TOTAL_KEYS=$(redis-cli -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE 2>/dev/null)
echo "  Total Keys: $TOTAL_KEYS"

echo ""

# Summary
log_success "=== All Tests Passed ==="
echo ""
log_info "Redis is fully operational!"
echo ""
log_info "Connection Details:"
echo "  Internal: redis-master.default.svc.cluster.local:6379"
echo "  External: localhost:30379 (or VM IP:30379)"
echo ""
log_info "To connect manually:"
echo "  redis-cli -h localhost -p 30379 -a <password>"
echo ""
log_info "To get credentials:"
echo "  ./scripts/utils/get-credentials.sh redis"
echo ""
log_info "Common Redis commands:"
echo "  SET key value    - Set a key"
echo "  GET key          - Get a key"
echo "  DEL key          - Delete a key"
echo "  KEYS *           - List all keys"
echo "  FLUSHALL         - Delete all keys (use with caution!)"

exit 0
