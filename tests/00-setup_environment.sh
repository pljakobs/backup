#!/bin/bash

# TEST_DESCRIPTION: set up environment and start containers
# TEST_TIMEOUT: 300

# Get container configuration from environment variables set by run-tests.sh
CLIENTS=${TEST_CONTAINER_CLIENTS:-1}
INFLUXDB=${TEST_CONTAINER_INFLUXDB:-true}
GRAFANA=${TEST_CONTAINER_GRAFANA:-true}

echo "Container configuration:"
echo "  Clients: $CLIENTS"
echo "  InfluxDB: $INFLUXDB"
echo "  Grafana: $GRAFANA"
echo

# Configure backup.yaml based on number of clients
if [[ "$CLIENTS" -gt 1 ]]; then
    echo "Configuring for multi-client setup ($CLIENTS clients)..."
    if [[ -f "./containers/backup-multi.yaml" ]]; then
        # Generate dynamic configuration for the specified number of clients
        echo "backup_base: \"/share/backup\"" > ./containers/backup-configured.yaml
        echo "lock_file: \"/tmp/backup.lock\"" >> ./containers/backup-configured.yaml
        echo "rsync_options: \"-avz --stats --delete\"" >> ./containers/backup-configured.yaml
        echo "log_level: \"INFO\"" >> ./containers/backup-configured.yaml
        echo "parallel_jobs: $CLIENTS" >> ./containers/backup-configured.yaml
        echo "" >> ./containers/backup-configured.yaml
        echo "hosts:" >> ./containers/backup-configured.yaml
        
        # Generate client configurations
        for ((i=1; i<=CLIENTS; i++)); do
            echo "  client$i:" >> ./containers/backup-configured.yaml
            echo "    hostname: \"backup-client-$i\"" >> ./containers/backup-configured.yaml
            echo "    ssh_user: \"testuser\"" >> ./containers/backup-configured.yaml
            echo "    ssh_key: \"/etc/backup/ssh_keys/backup_key\"" >> ./containers/backup-configured.yaml
            echo "    ssh_port: 22" >> ./containers/backup-configured.yaml
            echo "    ignore_ping: false" >> ./containers/backup-configured.yaml
            echo "    paths:" >> ./containers/backup-configured.yaml
            echo "      - path: \"/home/testuser/data\"" >> ./containers/backup-configured.yaml
            echo "        dest_subdir: \"testuser-data\"" >> ./containers/backup-configured.yaml
            echo "      - path: \"/etc/hostname\"" >> ./containers/backup-configured.yaml
            echo "        dest_subdir: \"system-config\"" >> ./containers/backup-configured.yaml
        done
        
        echo "Generated dynamic configuration for $CLIENTS clients"
    else
        echo "ERROR: Multi-client template not found"
        exit 1
    fi
else
    echo "Configuring for single-client setup..."
    if [[ -f "./containers/backup.yaml" ]]; then
        # Use single client configuration but fix hostname
        sed 's/hostname: "client"/hostname: "backup-client-1"/' ./containers/backup.yaml > ./containers/backup-configured.yaml
        echo "Configured single-client setup with correct hostname"
    else
        echo "ERROR: Single-client template not found"
        exit 1
    fi
fi

# Export configuration for the container script
export CONTAINER_CLIENTS="$CLIENTS"
export CONTAINER_INFLUXDB="$INFLUXDB"
export CONTAINER_GRAFANA="$GRAFANA"

# Use the container setup from the tests/containers subfolder
./containers/test-environment.sh start