#!/bin/bash

#############################################
# backup-postgresql.sh
# 
# Purpose: Backup PostgreSQL databases using pg_dumpall
# Requirements: PostgreSQL pod running, psql client installed
# 
# What it does:
#   - Retrieves PostgreSQL credentials from Kubernetes secret
#   - Connects to PostgreSQL and dumps all databases
#   - Compresses backup with gzip
#   - Saves backup with timestamp
#   - Creates metadata JSON file
#   - Implements retention policy (deletes old backups)
#   - Logs success or failure
#
# Usage: ./backup-postgresql.sh
# Typically run by Kubernetes CronJob
#############################################

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups/postgresql}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
POSTGRES_HOST="${POSTGRES_HOST:-postgresql.default.svc.cluster.local}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_info "Starting PostgreSQL backup..."

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate backup filename with timestamp
TIMESTAMP=$(date '+%Y-%m-%d-%H%M%S')
BACKUP_FILE="$BACKUP_DIR/postgresql-backup-$TIMESTAMP.sql"
BACKUP_FILE_GZ="$BACKUP_FILE.gz"
METADATA_FILE="$BACKUP_DIR/postgresql-backup-$TIMESTAMP.meta.json"

log_info "Backup file: $BACKUP_FILE_GZ"

# Retrieve PostgreSQL password from Kubernetes secret
log_info "Retrieving PostgreSQL credentials..."

if command -v kubectl &> /dev/null; then
    # Running inside cluster or with kubectl access
    POSTGRES_PASSWORD=$(kubectl get secret postgresql-secret -o jsonpath='{.data.postgres-password}' 2>/dev/null | base64 -d 2>/dev/null)
else
    # Running inside pod, use mounted secret
    if [ -f /var/run/secrets/postgresql/postgres-password ]; then
        POSTGRES_PASSWORD=$(cat /var/run/secrets/postgresql/postgres-password)
    else
        log_error "Cannot retrieve PostgreSQL password"
        log_error "kubectl not available and secret not mounted"
        exit 1
    fi
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    log_error "Failed to retrieve PostgreSQL password"
    exit 1
fi

log_success "Credentials retrieved"

# Set PGPASSWORD environment variable for pg_dumpall
export PGPASSWORD="$POSTGRES_PASSWORD"

# Check if PostgreSQL is accessible
log_info "Checking PostgreSQL connectivity..."

if ! psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "SELECT 1" > /dev/null 2>&1; then
    log_error "Cannot connect to PostgreSQL at $POSTGRES_HOST:$POSTGRES_PORT"
    log_error "Please check if PostgreSQL pod is running"
    exit 1
fi

log_success "PostgreSQL is accessible"

# Perform backup using pg_dumpall
log_info "Starting database dump..."
log_info "This may take a while depending on database size..."

BACKUP_START_TIME=$(date +%s)

if pg_dumpall -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" > "$BACKUP_FILE" 2>/dev/null; then
    BACKUP_END_TIME=$(date +%s)
    BACKUP_DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))
    
    log_success "Database dump completed in ${BACKUP_DURATION}s"
    
    # Compress backup
    log_info "Compressing backup..."
    
    if gzip "$BACKUP_FILE"; then
        BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE_GZ" 2>/dev/null || stat -c%s "$BACKUP_FILE_GZ" 2>/dev/null)
        BACKUP_SIZE_MB=$((BACKUP_SIZE / 1024 / 1024))
        
        log_success "Backup compressed (size: ${BACKUP_SIZE_MB}MB)"
    else
        log_error "Failed to compress backup"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
else
    log_error "Database dump failed"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Create metadata file
log_info "Creating metadata file..."

cat > "$METADATA_FILE" <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "backup_file": "$(basename "$BACKUP_FILE_GZ")",
  "database_host": "$POSTGRES_HOST",
  "database_port": $POSTGRES_PORT,
  "size_bytes": $BACKUP_SIZE,
  "size_mb": $BACKUP_SIZE_MB,
  "duration_seconds": $BACKUP_DURATION,
  "status": "success",
  "retention_days": $RETENTION_DAYS
}
EOF

log_success "Metadata file created"

# Implement retention policy
log_info "Applying retention policy (keeping last $RETENTION_DAYS days)..."

DELETED_COUNT=0

# Find and delete old backups
find "$BACKUP_DIR" -name "postgresql-backup-*.sql.gz" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null | while IFS= read -r -d '' old_backup; do
    log_info "Deleting old backup: $(basename "$old_backup")"
    rm -f "$old_backup"
    
    # Also delete corresponding metadata file
    metadata_file="${old_backup%.sql.gz}.meta.json"
    if [ -f "$metadata_file" ]; then
        rm -f "$metadata_file"
    fi
    
    DELETED_COUNT=$((DELETED_COUNT + 1))
done

if [ $DELETED_COUNT -gt 0 ]; then
    log_info "Deleted $DELETED_COUNT old backup(s)"
else
    log_info "No old backups to delete"
fi

# Display backup summary
echo ""
log_success "=== Backup Summary ==="
log_info "Backup file: $(basename "$BACKUP_FILE_GZ")"
log_info "Backup size: ${BACKUP_SIZE_MB}MB"
log_info "Duration: ${BACKUP_DURATION}s"
log_info "Location: $BACKUP_DIR"
log_info "Retention: $RETENTION_DAYS days"

# List recent backups
echo ""
log_info "Recent backups:"
ls -lh "$BACKUP_DIR"/postgresql-backup-*.sql.gz 2>/dev/null | tail -5 || log_info "No backups found"

# Unset password
unset PGPASSWORD

log_success "Backup completed successfully!"

exit 0
