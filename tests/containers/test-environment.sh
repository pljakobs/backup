#!/bin/bash
# Podman orchestration script for backup testing environment

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$(dirname "$TESTS_DIR")"
cd "$BACKUP_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if podman is available
check_podman() {
    if ! command -v podman &> /dev/null; then
        error "Podman is not installed. Please install podman first."
        exit 1
    fi
    log "Podman version: $(podman --version)"
}

# Function to create network
create_network() {
    local network_name="backup-test-network"
    
    if podman network exists "$network_name" 2>/dev/null; then
        log "Network $network_name already exists"
    else
        log "Creating network: $network_name"
        podman network create "$network_name"
        success "Network created: $network_name"
    fi
}

# Function to build containers
build_containers() {
    log "Building containers..."
    
    currentDir=`pwd`

    log "current directory $currentDir"
    # Build backup container
    log "Building backup container..."
    podman build -f tests/containers/Containerfile.backup -t backup-test:latest .
    
    # Build client container
    log "Building client container..."
    podman build -f tests/containers/Containerfile.client -t backup-client:latest .
    
    # Build InfluxDB container (if custom)
    if [[ -f tests/containers/Containerfile.influxdb ]]; then
        log "Building InfluxDB container..."
        podman build -f tests/containers/Containerfile.influxdb -t backup-influxdb:latest .
    fi
    
    # Build Grafana container (if custom)
    if [[ -f tests/containers/Containerfile.grafana ]]; then
        log "Building Grafana container..."
        podman build -f tests/containers/Containerfile.grafana -t backup-grafana:latest .
    fi
    
    success "All containers built successfully"
}

# Function to start InfluxDB
start_influxdb() {
    local container_name="backup-influxdb"
    
    if podman ps -q -f name="$container_name" | grep -q .; then
        log "InfluxDB container already running"
        return 0
    fi
    
    log "Starting InfluxDB container..."
    podman run -d \
        --name "$container_name" \
        --hostname influxdb \
        --network backup-test-network \
        -p 8086:8086 \
        -e DOCKER_INFLUXDB_INIT_MODE=setup \
        -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
        -e DOCKER_INFLUXDB_INIT_PASSWORD=backup-admin-password \
        -e DOCKER_INFLUXDB_INIT_ORG=backup-org \
        -e DOCKER_INFLUXDB_INIT_BUCKET=backup-metrics \
        -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=backup-test-token \
        -v influxdb-data:/var/lib/influxdb2 \
        -v influxdb-config:/etc/influxdb2 \
        docker.io/influxdb:2.7-alpine
    
    # Wait for InfluxDB to be ready
    log "Waiting for InfluxDB to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8086/health > /dev/null 2>&1; then
            success "InfluxDB is ready"
            return 0
        fi
        sleep 2
    done
    
    error "InfluxDB failed to start properly"
    return 1
}

# Function to start Grafana
start_grafana() {
    local container_name="backup-grafana"
    
    if podman ps -q -f name="$container_name" | grep -q .; then
        log "Grafana container already running"
        return 0
    fi
    
    log "Starting Grafana container..."
    podman run -d \
        --name "$container_name" \
        --hostname grafana \
        --network backup-test-network \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_PASSWORD=backup-grafana-password \
        -v grafana-data:/var/lib/grafana \
        -v "$(pwd)/tests/containers/grafana/provisioning:/etc/grafana/provisioning:ro" \
        -v "$(pwd)/tests/containers/grafana/dashboards:/var/lib/grafana/dashboards:ro" \
        docker.io/grafana/grafana:10.2.3
    
    # Wait for Grafana to be ready
    log "Waiting for Grafana to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
            success "Grafana is ready"
            return 0
        fi
        sleep 2
    done
    
    warning "Grafana may not be fully ready yet"
}

# Function to start client(s)
start_client() {
    local num_clients=${CONTAINER_CLIENTS:-1}
    
    log "Starting $num_clients client container(s)..."
    
    for ((i=1; i<=num_clients; i++)); do
        local container_name="backup-client-$i"
        local ssh_port=$((2220 + i))
        local hostname="client$i"
        
        if podman ps -q -f name="$container_name" | grep -q .; then
            log "Client container $container_name already running"
            continue
        fi
        
        log "Starting client container $i on port $ssh_port..."
        podman run -d \
            --name "$container_name" \
            --hostname "$hostname" \
            --network backup-test-network \
            -p "$ssh_port:22" \
            -v "client-$i-data:/home/testuser/data" \
            -v backup-shared:/shared \
            backup-client:latest
        
        # Wait for SSH to be ready
        log "Waiting for SSH service on client $i (port $ssh_port)..."
        for j in {1..20}; do
            if nc -z localhost "$ssh_port" 2>/dev/null; then
                success "Client $i SSH service is ready on port $ssh_port"
                break
            fi
            sleep 1
        done
    done
    
    success "All $num_clients client containers started"
}

# Function to setup SSH keys
setup_ssh_keys() {
    log "Setting up SSH keys for backup access..."
    
    # Generate backup key if it doesn't exist
    local key_dir="$(pwd)/tests/containers/ssh_keys"
    mkdir -p "$key_dir"
    
    if [[ ! -f "$key_dir/backup_key" ]]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f "$key_dir/backup_key" -N ""
    fi
    
    # Copy public key to all client containers
    local num_clients=${CONTAINER_CLIENTS:-1}
    local pub_key=$(cat "$key_dir/backup_key.pub")
    
    for ((i=1; i<=num_clients; i++)); do
        local container_name="backup-client-$i"
        log "Adding public key to client $i..."
        if podman ps -q -f name="$container_name" | grep -q .; then
            podman exec "$container_name" bash -c "echo '$pub_key' >> /home/testuser/.ssh/authorized_keys"
        else
            warning "Client container $container_name not running, skipping SSH key setup"
        fi
    done
    
    success "SSH keys configured for $num_clients client(s)"
}

# Function to copy SSH keys to backup container with correct ownership
copy_ssh_keys_to_container() {
    local container_name="$1"
    local key_dir="$(pwd)/tests/containers/ssh_keys"
    
    log "Copying SSH keys to backup container with correct ownership..."
    
    # Create the SSH keys directory in the container
    podman exec "$container_name" mkdir -p /etc/backup/ssh_keys
    
    # Copy the SSH keys
    podman cp "$key_dir/backup_key" "$container_name:/etc/backup/ssh_keys/backup_key"
    podman cp "$key_dir/backup_key.pub" "$container_name:/etc/backup/ssh_keys/backup_key.pub"
    
    # Set correct ownership and permissions inside the container
    podman exec "$container_name" chown -R backup:backup /etc/backup/ssh_keys
    podman exec "$container_name" chmod 700 /etc/backup/ssh_keys
    podman exec "$container_name" chmod 600 /etc/backup/ssh_keys/backup_key
    podman exec "$container_name" chmod 644 /etc/backup/ssh_keys/backup_key.pub
    
    success "SSH keys copied to container with correct ownership"
}

# Function to start backup container
start_backup() {
    local container_name="backup-test"
    
    if podman ps -q -f name="$container_name" | grep -q .; then
        log "Backup container already running"
        # Update configuration if container is already running
        update_backup_config
        return 0
    fi
    
    log "Starting backup container..."
    podman run -d \
        --name "$container_name" \
        --network backup-test-network \
        --cap-add CAP_NET_RAW \
        -v backup-data:/var/lib/backup \
        -v backup-logs:/var/log/backup \
        -v backup-shared:/shared \
        -v "$(pwd):/opt/backup-source:ro" \
        -e INFLUXDB_URL=http://influxdb:8086 \
        -e INFLUXDB_TOKEN=backup-test-token \
        -e INFLUXDB_ORG=backup-org \
        -e INFLUXDB_BUCKET=backup-metrics \
        backup-test:latest \
        bash -c "sleep infinity"
    
    success "Backup container started"
    
    # Copy SSH keys with correct ownership
    copy_ssh_keys_to_container "$container_name"
    
    # Copy the configured backup.yaml file to the container
    update_backup_config
}

# Function to update backup configuration in container
update_backup_config() {
    local container_name="backup-test"
    local config_file="tests/containers/backup-configured.yaml"
    
    if [[ -f "$config_file" ]]; then
        log "Copying backup configuration to container..."
        podman cp "$config_file" "$container_name:/etc/backup/backup.yaml"
        success "Backup configuration updated"
    else
        error "Generated backup configuration file not found: $config_file"
        log "Current working directory: $(pwd)"
        log "Looking for file at: $(realpath "$config_file" 2>/dev/null || echo "path does not exist")"
        return 1
    fi
}

# Function to run tests
run_tests() {
    log "Running backup tests..."
    
    podman exec -it backup-test bash -c "
        cd /opt/backup
        ./tests/run-tests.sh
    "
}

# Function to show status
show_status() {
    log "Container status:"
    podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    
    echo ""
    log "Service URLs:"
    if [[ "${CONTAINER_INFLUXDB:-true}" == "true" ]]; then
        echo "  InfluxDB: http://localhost:8086 (admin/backup-admin-password)"
    fi
    if [[ "${CONTAINER_GRAFANA:-true}" == "true" ]]; then
        echo "  Grafana:  http://localhost:3000 (admin/backup-grafana-password)"
    fi
    
    echo ""
    log "Client SSH connections:"
    local num_clients=${CONTAINER_CLIENTS:-1}
    for ((i=1; i<=num_clients; i++)); do
        local ssh_port=$((2220 + i))
        echo "  Client $i: ssh -p $ssh_port testuser@localhost"
    done
    
    echo ""
    log "Useful commands:"
    echo "  podman exec -it backup-test bash       # Enter backup container"
    echo "  podman exec -it backup-client-1 bash   # Enter first client container"
    echo "  podman logs backup-test                # View backup logs"
    echo "  ./containers/test-environment.sh stop  # Stop all containers"
}

# Function to stop all containers
stop_containers() {
    log "Stopping all backup test containers..."
    
    # Stop main containers
    local main_containers=("backup-test" "backup-influxdb" "backup-grafana")
    
    for container in "${main_containers[@]}"; do
        if podman ps -q -f name="$container" | grep -q .; then
            log "Stopping $container..."
            podman stop "$container" || true
        fi
    done
    
    # Stop all client containers (discover them dynamically)
    local client_containers=$(podman ps --format "{{.Names}}" | grep "^backup-client-" || true)
    if [[ -n "$client_containers" ]]; then
        for container in $client_containers; do
            log "Stopping $container..."
            podman stop "$container" || true
        done
    fi
    
    success "All containers stopped"
}

# Function to clean up
cleanup() {
    log "Cleaning up containers and volumes..."
    
    stop_containers
    
    # Remove main containers
    local main_containers=("backup-test" "backup-influxdb" "backup-grafana")
    
    for container in "${main_containers[@]}"; do
        if podman ps -a -q -f name="$container" | grep -q .; then
            log "Removing $container..."
            podman rm "$container" || true
        fi
    done
    
    # Remove all client containers (discover them dynamically)
    local client_containers=$(podman ps -a --format "{{.Names}}" | grep "^backup-client-" || true)
    if [[ -n "$client_containers" ]]; then
        for container in $client_containers; do
            log "Removing $container..."
            podman rm "$container" || true
        done
    fi
    
    # Optionally remove volumes
    if [[ "${1:-}" == "--volumes" ]]; then
        log "Removing volumes..."
        # Remove main volumes
        podman volume rm backup-data backup-logs influxdb-data influxdb-config grafana-data 2>/dev/null || true
        
        # Remove client volumes (discover them dynamically)
        local client_volumes=$(podman volume ls --format "{{.Name}}" | grep "^client-.*-data" || true)
        if [[ -n "$client_volumes" ]]; then
            for volume in $client_volumes; do
                log "Removing volume $volume..."
                podman volume rm "$volume" 2>/dev/null || true
            done
        fi
    fi
    
    success "Cleanup complete"
}

# Main execution
main() {
    case "${1:-start}" in
        "start")
            check_podman
            create_network
            build_containers
            
            # Start services based on configuration
            if [[ "${CONTAINER_INFLUXDB:-true}" == "true" ]]; then
                start_influxdb
            else
                log "Skipping InfluxDB (disabled in configuration)"
            fi
            
            if [[ "${CONTAINER_GRAFANA:-true}" == "true" ]]; then
                start_grafana
            else
                log "Skipping Grafana (disabled in configuration)"
            fi
            
            start_client
            sleep 5  # Allow services to settle
            setup_ssh_keys
            start_backup
            show_status
            ;;
        "test")
            run_tests
            ;;
        "status")
            show_status
            ;;
        "stop")
            stop_containers
            ;;
        "clean")
            cleanup "${2:-}"
            ;;
        "restart")
            stop_containers
            sleep 2
            main start
            ;;
        *)
            echo "Usage: $0 {start|test|status|stop|clean|restart}"
            echo ""
            echo "Commands:"
            echo "  start    - Start all containers"
            echo "  test     - Run backup tests"
            echo "  status   - Show container status and URLs"
            echo "  stop     - Stop all containers"
            echo "  clean    - Remove all containers (add --volumes to also remove volumes)"
            echo "  restart  - Stop and start all containers"
            exit 1
            ;;
    esac
}

main "$@"
