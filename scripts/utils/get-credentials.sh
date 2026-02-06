#!/bin/bash

#############################################
# get-credentials.sh
# 
# Purpose: Retrieve credentials from Kubernetes secrets
# Usage: ./get-credentials.sh <service-name>
# Supported services: postgresql, redis
#
# Example:
#   ./get-credentials.sh postgresql
#   ./get-credentials.sh redis
#############################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if service name is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Service name required${NC}" >&2
    echo "Usage: $0 <service-name>" >&2
    echo "Supported services: postgresql, redis" >&2
    exit 1
fi

SERVICE=$1

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}" >&2
    echo "Please install kubectl first" >&2
    exit 1
fi

# Function to get secret value
get_secret() {
    local secret_name=$1
    local key=$2
    
    # Check if secret exists
    if ! kubectl get secret "$secret_name" &> /dev/null; then
        echo -e "${RED}Error: Secret '$secret_name' not found${NC}" >&2
        echo "Make sure the service is deployed first" >&2
        return 1
    fi
    
    # Get and decode secret
    local value
    value=$(kubectl get secret "$secret_name" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -z "$value" ]; then
        echo -e "${RED}Error: Key '$key' not found in secret '$secret_name'${NC}" >&2
        return 1
    fi
    
    echo "$value"
}

# Handle different services
case "$SERVICE" in
    postgresql)
        echo -e "${GREEN}=== PostgreSQL Credentials ===${NC}"
        echo ""
        
        POSTGRES_PASSWORD=$(get_secret "postgresql-secret" "postgres-password")
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}Admin User:${NC} postgres"
            echo -e "${YELLOW}Admin Password:${NC} $POSTGRES_PASSWORD"
        fi
        
        echo ""
        echo -e "${YELLOW}Internal Connection:${NC}"
        echo "  Host: postgresql.default.svc.cluster.local"
        echo "  Port: 5432"
        echo ""
        echo -e "${YELLOW}External Connection:${NC}"
        echo "  Host: localhost (or VM IP)"
        echo "  Port: 30432"
        echo ""
        echo -e "${YELLOW}Connection String:${NC}"
        echo "  psql -h localhost -p 30432 -U postgres -d postgres"
        ;;
        
    redis)
        echo -e "${GREEN}=== Redis Credentials ===${NC}"
        echo ""
        
        REDIS_PASSWORD=$(get_secret "redis-secret" "redis-password")
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}Password:${NC} $REDIS_PASSWORD"
        fi
        
        echo ""
        echo -e "${YELLOW}Internal Connection:${NC}"
        echo "  Host: redis-master.default.svc.cluster.local"
        echo "  Port: 6379"
        echo ""
        echo -e "${YELLOW}External Connection:${NC}"
        echo "  Host: localhost (or VM IP)"
        echo "  Port: 30379"
        echo ""
        echo -e "${YELLOW}Connection String:${NC}"
        echo "  redis-cli -h localhost -p 30379 -a <password>"
        ;;
        
    *)
        echo -e "${RED}Error: Unknown service '$SERVICE'${NC}" >&2
        echo "Supported services: postgresql, redis" >&2
        exit 1
        ;;
esac

exit 0
