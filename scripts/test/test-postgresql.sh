#!/bin/bash

#############################################
# test-postgresql.sh
# 
# Purpose: Test PostgreSQL connectivity (internal and external)
# Requirements: PostgreSQL deployed, psql client installed
# 
# What it does:
#   - Retrieves PostgreSQL credentials
#   - Tests internal cluster connection (cluster DNS)
#   - Tests external connection (NodePort)
#   - Executes sample SQL query
#   - Displays success or error messages
#
# Usage: ./test-postgresql.sh
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

# Check if psql is installed
if ! command -v psql &> /dev/null; then
    log_error "psql (PostgreSQL client) not found"
    log_error "Please install it: sudo apt-get install postgresql-client"
    exit 1
fi

log_info "=== PostgreSQL Connectivity Test ==="
echo ""

# Retrieve PostgreSQL credentials
log_info "Retrieving PostgreSQL credentials..."

# Try kubectl first (if available)
if command -v kubectl &> /dev/null; then
    POSTGRES_PASSWORD=$(kubectl get secret postgresql-secret -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d 2>/dev/null)
else
    log_error "kubectl not found. Cannot retrieve credentials."
    exit 1
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    log_error "Failed to retrieve PostgreSQL password"
    log_error "Make sure PostgreSQL is deployed: ./scripts/install/deploy-services.sh"
    exit 1
fi

log_success "Credentials retrieved"
echo ""

# Set PGPASSWORD environment variable
export PGPASSWORD="$POSTGRES_PASSWORD"

# Test 1: Internal Connection (Cluster DNS)
log_info "Test 1: Internal Connection (Cluster DNS)"
log_info "Connecting to: postgresql.default.svc.cluster.local:5432"

INTERNAL_HOST="postgresql.default.svc.cluster.local"
INTERNAL_PORT="5432"

if psql -h "$INTERNAL_HOST" -p "$INTERNAL_PORT" -U postgres -d postgres -c "SELECT version();" > /dev/null 2>&1; then
    log_success "Internal connection successful"
    
    # Get PostgreSQL version
    PG_VERSION=$(psql -h "$INTERNAL_HOST" -p "$INTERNAL_PORT" -U postgres -d postgres -t -c "SELECT version();" 2>/dev/null | head -n1 | xargs)
    echo "  Version: $PG_VERSION"
else
    log_error "Internal connection failed"
    log_warning "This is expected if running outside the Kubernetes cluster"
fi

echo ""

# Test 2: External Connection (NodePort)
log_info "Test 2: External Connection (NodePort)"
log_info "Connecting to: localhost:30432"

EXTERNAL_HOST="localhost"
EXTERNAL_PORT="30432"

if psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    log_success "External connection successful"
    
    # Execute sample query
    log_info "Executing sample query..."
    
    QUERY_RESULT=$(psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -t -c "SELECT current_database(), current_user, now();" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        log_success "Query executed successfully"
        echo ""
        echo "  Database: $(echo "$QUERY_RESULT" | awk '{print $1}')"
        echo "  User: $(echo "$QUERY_RESULT" | awk '{print $3}')"
        echo "  Timestamp: $(echo "$QUERY_RESULT" | awk '{print $5, $6}')"
    fi
else
    log_error "External connection failed"
    log_error "Possible reasons:"
    echo "  - PostgreSQL pod is not running"
    echo "  - NodePort service is not configured"
    echo "  - Firewall blocking port 30432"
    echo ""
    log_info "Check pod status: kubectl get pods -l app.kubernetes.io/name=postgresql"
    log_info "Check service: kubectl get svc postgresql"
    exit 1
fi

echo ""

# Test 3: Database Operations
log_info "Test 3: Database Operations"

# Create test table
log_info "Creating test table..."

if psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -c "
    DROP TABLE IF EXISTS connectivity_test;
    CREATE TABLE connectivity_test (
        id SERIAL PRIMARY KEY,
        test_name VARCHAR(100),
        test_time TIMESTAMP DEFAULT NOW()
    );
" > /dev/null 2>&1; then
    log_success "Test table created"
else
    log_error "Failed to create test table"
    exit 1
fi

# Insert test data
log_info "Inserting test data..."

if psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -c "
    INSERT INTO connectivity_test (test_name) VALUES ('PostgreSQL Connectivity Test');
" > /dev/null 2>&1; then
    log_success "Test data inserted"
else
    log_error "Failed to insert test data"
    exit 1
fi

# Query test data
log_info "Querying test data..."

TEST_DATA=$(psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -t -c "
    SELECT test_name, test_time FROM connectivity_test ORDER BY id DESC LIMIT 1;
" 2>/dev/null)

if [ $? -eq 0 ]; then
    log_success "Test data retrieved"
    echo "  Data: $TEST_DATA"
else
    log_error "Failed to query test data"
    exit 1
fi

# Clean up test table
log_info "Cleaning up test table..."

if psql -h "$EXTERNAL_HOST" -p "$EXTERNAL_PORT" -U postgres -d postgres -c "
    DROP TABLE connectivity_test;
" > /dev/null 2>&1; then
    log_success "Test table dropped"
else
    log_warning "Failed to drop test table (not critical)"
fi

echo ""

# Summary
log_success "=== All Tests Passed ==="
echo ""
log_info "PostgreSQL is fully operational!"
echo ""
log_info "Connection Details:"
echo "  Internal: postgresql.default.svc.cluster.local:5432"
echo "  External: localhost:30432 (or VM IP:30432)"
echo "  Database: postgres"
echo "  User: postgres"
echo ""
log_info "To connect manually:"
echo "  psql -h localhost -p 30432 -U postgres -d postgres"
echo ""
log_info "To get credentials:"
echo "  ./scripts/utils/get-credentials.sh postgresql"

# Unset password
unset PGPASSWORD

exit 0
