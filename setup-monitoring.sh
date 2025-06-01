#!/bin/bash

# Backup Monitoring Setup Script
# This script sets up the complete backup monitoring system with Grafana

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Run as your regular user with sudo access."
    exit 1
fi

print_header "Backup Monitoring Setup"

# Create directories
print_info "Creating necessary directories..."
sudo mkdir -p /etc/backup
sudo mkdir -p /var/lib/node_exporter
sudo mkdir -p /usr/local/bin

# Copy configuration if it doesn't exist
if [[ ! -f /etc/backup/backup.yaml ]]; then
    if [[ -f backup.yaml ]]; then
        print_info "Copying backup configuration..."
        sudo cp backup.yaml /etc/backup/backup.yaml
        print_success "Backup configuration copied to /etc/backup/backup.yaml"
    else
        print_warning "No backup.yaml found in current directory. Creating minimal config..."
        sudo tee /etc/backup/backup.yaml > /dev/null <<EOF
backup_base: "/share/backup"
lock_file: "/tmp/backup.lock"
rsync_opts: "-avhH --delete --stats"
hosts:
  example:
    ssh_user: "user"
    hostname: "example.com"
    ignore_ping: false
    paths:
      - source: "/home/user"
        destination: "home"
      - source: "/etc"
        destination: "etc"
EOF
        print_warning "Please edit /etc/backup/backup.yaml with your actual configuration"
    fi
fi

# Install Python dependencies
print_info "Installing Python dependencies..."
if command -v pip3 &> /dev/null; then
    pip3 install --user pyyaml
    print_success "Python dependencies installed"
else
    print_error "pip3 not found. Please install python3-pip package"
    exit 1
fi

# Install backup metrics script
print_info "Installing backup metrics collector..."
if [[ -f backup-metrics.py ]]; then
    sudo cp backup-metrics.py /usr/local/bin/backup-metrics.py
    sudo chmod +x /usr/local/bin/backup-metrics.py
    print_success "Backup metrics script installed"
else
    print_error "backup-metrics.py not found in current directory"
    exit 1
fi

# Install systemd service and timer
print_info "Installing systemd service and timer..."
if [[ -f backup-metrics.service ]] && [[ -f backup-metrics.timer ]]; then
    sudo cp backup-metrics.service /etc/systemd/system/
    sudo cp backup-metrics.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    print_success "Systemd service and timer installed"
else
    print_error "backup-metrics.service or backup-metrics.timer not found"
    exit 1
fi

# Check if Prometheus Node Exporter is installed
print_info "Checking for Prometheus Node Exporter..."
if systemctl list-units --type=service | grep -q node_exporter; then
    print_success "Node Exporter service found"
    
    # Check if textfile collector is enabled
    if systemctl cat node_exporter | grep -q "collector.textfile.directory"; then
        print_success "Textfile collector appears to be configured"
    else
        print_warning "Node Exporter may not have textfile collector enabled"
        print_info "Ensure Node Exporter is started with: --collector.textfile.directory=/var/lib/node_exporter"
    fi
else
    print_warning "Node Exporter not found. Installing..."
    
    # Download and install Node Exporter
    NODE_EXPORTER_VERSION="1.6.1"
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"*
    
    # Create node_exporter user
    sudo useradd --no-create-home --shell /bin/false node_exporter || true
    
    # Create systemd service
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter
    print_success "Node Exporter installed and started"
fi

# Set permissions for metrics directory
sudo chown node_exporter:node_exporter /var/lib/node_exporter
sudo chmod 755 /var/lib/node_exporter

# Start and enable backup metrics timer
print_info "Starting backup metrics collection..."
sudo systemctl enable backup-metrics.timer
sudo systemctl start backup-metrics.timer
print_success "Backup metrics timer enabled and started"

# Test metrics collection
print_info "Testing metrics collection..."
sudo /usr/local/bin/backup-metrics.py --prometheus
if [[ -f /var/lib/node_exporter/backup_metrics.prom ]]; then
    print_success "Metrics collection working"
    print_info "Sample metrics:"
    head -5 /var/lib/node_exporter/backup_metrics.prom
else
    print_error "Metrics collection failed"
fi

print_header "Installation Complete"
print_success "Backup monitoring system installed successfully!"
print_info ""
print_info "Next steps:"
print_info "1. Configure Prometheus to scrape Node Exporter (usually port 9100)"
print_info "2. Import the Grafana dashboard from grafana-dashboard.json"
print_info "3. Edit /etc/backup/backup.yaml with your actual backup configuration"
print_info ""
print_info "Commands to check status:"
print_info "  sudo systemctl status backup-metrics.timer"
print_info "  sudo systemctl status node_exporter"
print_info "  curl http://localhost:9100/metrics | grep backup"
print_info ""
print_info "Log locations:"
print_info "  sudo journalctl -u backup-metrics.service"
print_info "  sudo journalctl -u backup.service"
