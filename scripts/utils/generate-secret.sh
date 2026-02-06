#!/bin/bash

#############################################
# generate-secret.sh
# 
# Purpose: Generate cryptographically secure random passwords
# Usage: ./generate-secret.sh [length]
# Default length: 32 characters
#
# Example:
#   ./generate-secret.sh      # Generates 32-char password
#   ./generate-secret.sh 16   # Generates 16-char password
#############################################

set -e  # Exit on error

# Default password length
DEFAULT_LENGTH=32

# Get length from argument or use default
LENGTH=${1:-$DEFAULT_LENGTH}

# Validate length is a positive integer
if ! [[ "$LENGTH" =~ ^[0-9]+$ ]] || [ "$LENGTH" -lt 8 ]; then
    echo "Error: Length must be a positive integer >= 8" >&2
    echo "Usage: $0 [length]" >&2
    exit 1
fi

# Generate password using openssl
# - Uses /dev/urandom for cryptographically secure randomness
# - base64 encoding ensures printable characters
# - tr removes characters that might cause issues in YAML/shell
# - head ensures exact length
PASSWORD=$(openssl rand -base64 48 | tr -d '/+=' | head -c "$LENGTH")

# Verify password was generated
if [ -z "$PASSWORD" ]; then
    echo "Error: Failed to generate password" >&2
    exit 1
fi

# Verify password meets length requirement
if [ ${#PASSWORD} -ne "$LENGTH" ]; then
    echo "Error: Generated password length mismatch" >&2
    exit 1
fi

# Output password (no newline for easy piping)
echo -n "$PASSWORD"

exit 0
