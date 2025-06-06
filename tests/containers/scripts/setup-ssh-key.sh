#!/bin/bash
# Setup SSH key for backup access

if [ -z "$BACKUP_PUBLIC_KEY" ]; then
    echo "Error: BACKUP_PUBLIC_KEY environment variable not set"
    exit 1
fi

echo "$BACKUP_PUBLIC_KEY" >> /home/testuser/.ssh/authorized_keys
echo "SSH key added for backup access"
