#!/bin/bash
# Test runner specifically for containerized environment

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Test environment setup
test_container_setup() {
    log "Testing container environment setup..."
    
    # Check if we're running in a container
    if [[ -f /.dockerenv ]] || grep -q 'container=' /proc/1/environ 2>/dev/null; then
        success "Running in container environment"
    else
        warning "Not running in a container"
    fi
    
    # Check required files
    local required_files=(
        "/opt/backup/backup-new.sh"
        "/opt/backup/backup-metrics"
        "/etc/backup/backup.yaml"
        "/etc/backup/influxdb-config.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            success "Found required file: $file"
        else
            error "Missing required file: $file"
            return 1
        fi
    done
    
    # Check SSH key
    if [[ -f "/etc/backup/ssh_keys/backup_key" ]]; then
        success "SSH key found"
    else
        error "SSH key not found"
        return 1
    fi
}

# Test network connectivity
test_connectivity() {
    log "Testing network connectivity..."
    
    # Test InfluxDB connectivity
    if curl -s http://influxdb:8086/health > /dev/null; then
        success "InfluxDB is reachable"
    else
        error "Cannot reach InfluxDB"
        return 1
    fi
    
    # Test client SSH connectivity
    if nc -z client 22 2>/dev/null; then
        success "Client SSH port is open"
    else
        error "Cannot reach client SSH"
        return 1
    fi
    
    # Test SSH key authentication
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -i /etc/backup/ssh_keys/backup_key testuser@client "echo 'SSH OK'" 2>/dev/null; then
        success "SSH key authentication works"
    else
        warning "SSH key authentication failed (may need manual setup)"
    fi
}

# Test backup script execution
test_backup_execution() {
    log "Testing backup script execution..."
    
    # Test dry run
    if /opt/backup/backup-new.sh --dry-run 2>/dev/null; then
        success "Backup dry run completed"
    else
        error "Backup dry run failed"
        return 1
    fi
    
    # Test actual backup
    log "Running actual backup test..."
    if /opt/backup/backup-new.sh --verbose 2>&1 | tee /tmp/backup-test.log; then
        success "Backup execution completed"
        
        # Check for run ID in output
        if grep -q "Run ID:" /tmp/backup-test.log; then
            success "Run ID generated correctly"
        else
            warning "Run ID not found in backup output"
        fi
    else
        error "Backup execution failed"
        return 1
    fi
}

# Test metrics collection
test_metrics_collection() {
    log "Testing metrics collection..."
    
    # Test last run display
    if /opt/backup/backup-metrics --last-run 2>&1 | tee /tmp/metrics-test.log; then
        success "Metrics collection works"
        
        # Check for run ID in metrics
        if grep -q "Run ID:" /tmp/metrics-test.log; then
            success "Run ID found in metrics"
        else
            warning "Run ID not found in metrics output"
        fi
    else
        error "Metrics collection failed"
        return 1
    fi
    
    # Test InfluxDB data submission
    log "Testing InfluxDB data submission..."
    if /opt/backup/backup-metrics --submit-metrics 2>&1; then
        success "Metrics submission completed"
    else
        warning "Metrics submission may have failed"
    fi
}

# Test InfluxDB data
test_influxdb_data() {
    log "Testing InfluxDB data..."
    
    # Query recent backup data
    local query='from(bucket: "backup-metrics") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "backup_session")'
    
    if curl -s -H "Authorization: Token backup-test-token" \
            -H "Content-Type: application/vnd.flux" \
            -d "$query" \
            http://influxdb:8086/api/v2/query?org=backup-org | grep -q "_time"; then
        success "InfluxDB contains backup data"
    else
        warning "No backup data found in InfluxDB (may be expected if no backups have run)"
    fi
}

# Generate test report
generate_report() {
    log "Generating test report..."
    
    local report_file="/tmp/container-test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
Container Backup Test Report
Generated: $(date)
============================

Environment:
- Container: $(hostname)
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- Python: $(python3 --version)
- Backup Script: $(ls -la /opt/backup/backup-new.sh)
- Metrics Script: $(ls -la /opt/backup/backup-metrics)

Configuration Files:
$(ls -la /etc/backup/)

Test Results:
EOF
    
    # Append test logs if they exist
    if [[ -f /tmp/backup-test.log ]]; then
        echo -e "\n--- Backup Test Output ---" >> "$report_file"
        cat /tmp/backup-test.log >> "$report_file"
    fi
    
    if [[ -f /tmp/metrics-test.log ]]; then
        echo -e "\n--- Metrics Test Output ---" >> "$report_file"
        cat /tmp/metrics-test.log >> "$report_file"
    fi
    
    success "Test report generated: $report_file"
    echo "Report location: $report_file"
}

# Main test execution
main() {
    log "Starting containerized backup tests..."
    
    local failed_tests=0
    
    # Run tests
    test_container_setup || ((failed_tests++))
    test_connectivity || ((failed_tests++))
    test_backup_execution || ((failed_tests++))
    test_metrics_collection || ((failed_tests++))
    test_influxdb_data || ((failed_tests++))
    
    # Generate report
    generate_report
    
    # Summary
    echo ""
    if [[ $failed_tests -eq 0 ]]; then
        success "All container tests passed!"
        log "The backup system is working correctly in the containerized environment."
    else
        error "$failed_tests test(s) failed"
        log "Check the test output above for details."
        exit 1
    fi
    
    log "Test URLs for manual verification:"
    echo "  InfluxDB: http://localhost:8086 (admin/backup-admin-password)"
    echo "  Grafana:  http://localhost:3000 (admin/backup-grafana-password)"
}

main "$@"
