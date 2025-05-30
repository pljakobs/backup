#!/bin/bash
# Centralized InfluxDB Setup Script for Backup Monitoring
# This script configures backup monitoring to use an existing InfluxDB instance

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
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
   print_error "This script should not be run as root"
   exit 1
fi

print_header "Backup Monitoring Setup - Centralized InfluxDB"

# Configuration variables
CONFIG_DIR="/etc/backup"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

print_info "Configuration will be installed to: $CONFIG_DIR"
print_info "Scripts will be copied from current directory: $(pwd)"

# Create directories
print_info "Creating configuration directories..."
sudo mkdir -p "$CONFIG_DIR"
mkdir -p "$SYSTEMD_USER_DIR"
print_success "Directories created"

# Install Python dependencies
print_info "Installing Python dependencies..."
if command -v pip3 &> /dev/null; then
    pip3 install --user pyyaml requests
    print_success "Python dependencies installed"
else
    print_error "pip3 not found. Please install python3-pip package"
    exit 1
fi

# Copy backup configuration files
print_info "Installing backup configuration files..."
if [ -f "./backup.yaml" ]; then
    sudo cp "./backup.yaml" "$CONFIG_DIR/"
    print_success "Backup configuration copied to $CONFIG_DIR/backup.yaml"
else
    print_error "backup.yaml not found in current directory"
    exit 1
fi

# Copy InfluxDB configuration
if [ -f "./influxdb-config.yaml" ]; then
    sudo cp "./influxdb-config.yaml" "$CONFIG_DIR/"
    print_success "InfluxDB configuration copied to $CONFIG_DIR/influxdb-config.yaml"
else
    print_error "influxdb-config.yaml not found in current directory"
    exit 1
fi

# Copy and install backup scripts
print_info "Installing backup scripts..."
if [ -f "./backup-new.sh" ]; then
    sudo cp "./backup-new.sh" "/usr/local/bin/backup.sh"
    sudo chmod +x "/usr/local/bin/backup.sh"
    print_success "Backup script installed to /usr/local/bin/backup.sh"
else
    print_error "backup-new.sh not found in current directory"
    exit 1
fi

if [ -f "./backup-metrics.py" ]; then
    sudo cp "./backup-metrics.py" "/usr/local/bin/backup-metrics.py"
    sudo chmod +x "/usr/local/bin/backup-metrics.py"
    print_success "Backup metrics script installed to /usr/local/bin/backup-metrics.py"
else
    print_error "backup-metrics.py not found in current directory"
    exit 1
fi

# Copy other required files if they exist
if [ -f "./job_pool.sh" ]; then
    sudo cp "./job_pool.sh" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/job_pool.sh"
    print_success "Job pool script installed to /usr/local/bin/job_pool.sh"
fi

if [ -f "./options" ]; then
    sudo cp "./options" "$CONFIG_DIR/"
    print_success "Options file copied to $CONFIG_DIR/options"
fi

# Create systemd service for backup
print_info "Creating systemd service for backup..."
cat > "$SYSTEMD_USER_DIR/backup.service" << 'EOF'
[Unit]
Description=Automated Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh --backup
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

print_success "Backup service created"

# Create systemd timer for backup
print_info "Creating systemd timer for backup..."
cat > "$SYSTEMD_USER_DIR/backup.timer" << 'EOF'
[Unit]
Description=Run backup service every 2 hours
Requires=backup.service

[Timer]
OnCalendar=*:0/2:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

print_success "Backup timer created (runs every 2 hours)"

# Create systemd service for metrics collection
print_info "Creating systemd service for metrics collection..."
cat > "$SYSTEMD_USER_DIR/backup-metrics.service" << 'EOF'
[Unit]
Description=Backup Metrics Collection
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-metrics.py --send-influxdb
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

print_success "Backup metrics service created"

# Create systemd timer for metrics collection
print_info "Creating systemd timer for metrics collection..."
cat > "$SYSTEMD_USER_DIR/backup-metrics.timer" << 'EOF'
[Unit]
Description=Collect backup metrics every 5 minutes
Requires=backup-metrics.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

print_success "Backup metrics timer created"

# Enable systemd services
print_info "Enabling systemd services..."
systemctl --user daemon-reload
systemctl --user enable backup.timer
systemctl --user enable backup-metrics.timer
print_success "Systemd services enabled"

# Test metrics collection
print_info "Testing metrics collection..."
if /usr/local/bin/backup-metrics.py --json > /tmp/test-metrics.json; then
    print_success "Metrics collection test successful"
    print_info "Test output saved to /tmp/test-metrics.json"
else
    print_warning "Metrics collection test failed - check logs after configuration"
fi

print_header "Configuration Complete"

print_success "Backup monitoring setup completed!"
echo
print_info "Next steps:"
echo -e "  1. ${YELLOW}Edit $CONFIG_DIR/influxdb-config.yaml${NC} with your InfluxDB server details:"
echo -e "     - Set host, port, database name"
echo -e "     - Set username/password if authentication is required"
echo -e "     - Set ssl: true if using HTTPS"
echo
echo -e "  2. ${YELLOW}Test the InfluxDB connection:${NC}"
echo -e "     /usr/local/bin/backup-metrics.py --send-influxdb"
echo
echo -e "  3. ${YELLOW}Start the timers:${NC}"
echo -e "     systemctl --user start backup.timer"
echo -e "     systemctl --user start backup-metrics.timer"
echo
echo -e "  4. ${YELLOW}Check service status:${NC}"
echo -e "     systemctl --user status backup.timer"
echo -e "     systemctl --user status backup-metrics.timer"
echo
echo -e "  5. ${YELLOW}Check logs:${NC}"
echo -e "     journalctl --user -f -u backup.service"
echo -e "     journalctl --user -f -u backup-metrics.service"
echo
print_info "Database creation command for InfluxDB:"
echo -e "  ${CYAN}CREATE DATABASE backup_metrics${NC}"
echo
print_info "Configuration files:"
echo -e "  - Backup config: ${CYAN}$CONFIG_DIR/backup.yaml${NC}"
echo -e "  - InfluxDB config: ${CYAN}$CONFIG_DIR/influxdb-config.yaml${NC}"
echo -e "  - Backup script: ${CYAN}/usr/local/bin/backup.sh${NC}"
echo -e "  - Metrics script: ${CYAN}/usr/local/bin/backup-metrics.py${NC}"