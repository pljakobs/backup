#!/bin/bash

# Script to generate docker-compose.yml with configurable number of clients
# Usage: ./setup-clients.sh [number_of_clients] [base_port]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUM_CLIENTS="${1:-3}"
BASE_PORT="${2:-2222}"

echo "Setting up backup environment with $NUM_CLIENTS clients..."

# Validate inputs
if ! [[ "$NUM_CLIENTS" =~ ^[0-9]+$ ]] || [ "$NUM_CLIENTS" -lt 1 ] || [ "$NUM_CLIENTS" -gt 50 ]; then
    echo "Error: Number of clients must be between 1 and 50"
    exit 1
fi

if ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [ "$BASE_PORT" -lt 1024 ] || [ "$BASE_PORT" -gt 65000 ]; then
    echo "Error: Base port must be between 1024 and 65000"
    exit 1
fi

# Generate client services
CLIENT_SERVICES=""
CLIENT_DEPENDENCIES=""
CLIENT_VOLUMES=""

for i in $(seq 1 $NUM_CLIENTS); do
    CLIENT_NAME="client$i"
    CLIENT_PORT=$((BASE_PORT + i - 1))
    
    # Add to dependencies
    if [ $i -eq 1 ]; then
        CLIENT_DEPENDENCIES="      - $CLIENT_NAME"
    else
        CLIENT_DEPENDENCIES="$CLIENT_DEPENDENCIES
      - $CLIENT_NAME"
    fi
    
    # Add client volume
    CLIENT_VOLUMES="$CLIENT_VOLUMES
  ${CLIENT_NAME}-data:"
    
    # Generate client service definition
    CLIENT_SERVICE="  $CLIENT_NAME:
    build:
      context: .
      dockerfile: containers/Containerfile.client
    container_name: backup-$CLIENT_NAME
    hostname: $CLIENT_NAME
    networks:
      - backup-network
    volumes:
      - ${CLIENT_NAME}-data:/home/testuser/data
      - ssh-keys:/shared/ssh-keys
    ports:
      - \"$CLIENT_PORT:22\"
    environment:
      - CLIENT_ID=$i
      - CLIENT_NAME=$CLIENT_NAME"

    if [ $i -eq 1 ]; then
        CLIENT_SERVICES="$CLIENT_SERVICE"
    else
        CLIENT_SERVICES="$CLIENT_SERVICES

$CLIENT_SERVICE"
    fi
done

# Read template and replace placeholders
TEMPLATE_FILE="$SCRIPT_DIR/docker-compose.template.yml"
OUTPUT_FILE="$SCRIPT_DIR/docker-compose.yml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found"
    exit 1
fi

# Create docker-compose.yml from template
# Use Python for reliable multi-line replacements
python3 << EOF
import sys

with open('$TEMPLATE_FILE', 'r') as f:
    content = f.read()

content = content.replace('{{CLIENT_DEPENDENCIES}}', '''$CLIENT_DEPENDENCIES''')
content = content.replace('{{CLIENT_SERVICES}}', '''$CLIENT_SERVICES''')
content = content.replace('{{CLIENT_VOLUMES}}', '''$CLIENT_VOLUMES''')

with open('$OUTPUT_FILE', 'w') as f:
    f.write(content)
EOF

echo "✓ Generated docker-compose.yml with $NUM_CLIENTS clients"
echo "✓ Client SSH ports: $(seq -s", " $BASE_PORT $((BASE_PORT + NUM_CLIENTS - 1)))"

# Generate backup configuration for multiple clients
generate_backup_config() {
    local config_file="$SCRIPT_DIR/containers/backup-multi.yaml"
    
    cat > "$config_file" << EOF
backup_base: "/var/lib/backup/data"
lock_file: "/var/lib/backup/backup.lock"
rsync_options: "-avz --stats --delete"
log_level: "INFO"
parallel_jobs: $(($NUM_CLIENTS > 8 ? 8 : $NUM_CLIENTS))

hosts:
EOF

    for i in $(seq 1 $NUM_CLIENTS); do
        CLIENT_NAME="client$i"
        SSH_PORT=$((BASE_PORT + i - 1))
        cat >> "$config_file" << EOF
  $CLIENT_NAME:
    hostname: "$CLIENT_NAME"
    ssh_user: "testuser"
    ssh_key: "/etc/backup/ssh_keys/backup_key"
    ssh_port: $SSH_PORT
    ignore_ping: false
    paths:
      - path: "/home/testuser/data"
        dest_subdir: "testuser-data"
      - path: "/etc/hostname"
        dest_subdir: "system-config"
EOF
    done
    
    echo "✓ Generated backup configuration: $config_file"
}

generate_backup_config

# Update Containerfile to use the new configuration
update_containerfile() {
    local containerfile="$SCRIPT_DIR/containers/Containerfile.backup"
    local backup_file="${containerfile}.backup"
    
    # Create backup
    cp "$containerfile" "$backup_file"
    
    # Replace the backup configuration copy with the multi-client version
    sed -i 's|COPY containers/backup.yaml /etc/backup/|COPY containers/backup-multi.yaml /etc/backup/backup.yaml|g' "$containerfile" || true
    
    echo "✓ Updated Containerfile to use multi-client configuration"
}

# Check if backup-multi.yaml should be copied in Containerfile
if grep -q "backup-multi.yaml" "$SCRIPT_DIR/containers/Containerfile.backup"; then
    echo "✓ Containerfile already configured for multi-client setup"
else
    update_containerfile
fi

echo ""
echo "Setup complete! To start the environment:"
echo "  podman-compose up -d"
echo ""
echo "To test the backup:"
echo "  podman exec backup-test ./backup-new.sh --verify-hosts"
echo "  podman exec backup-test ./backup-new.sh --dry-run"
echo ""
echo "Client access (SSH):"
for i in $(seq 1 $NUM_CLIENTS); do
    CLIENT_PORT=$((BASE_PORT + i - 1))
    echo "  ssh -p $CLIENT_PORT testuser@localhost  # client$i"
done
