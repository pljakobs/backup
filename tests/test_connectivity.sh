#!/bin/bash

# Test script for verifying connectivity between backup and client containers
# Uses the --verify-hosts option of backup-new.sh

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
SCRIPT_NAME="test_connectivity.sh"
BACKUP_CONTAINER="backup-test"
BACKUP_SCRIPT="/opt/backup/backup-new.sh"

# Main test functions
test_container_running() {
    log_info "Testing if backup container is running..."
    run_test
    
    if podman ps --format "{{.Names}}" | grep -q "^${BACKUP_CONTAINER}$"; then
        log_success "Backup container '${BACKUP_CONTAINER}' is running"
        return 0
    else
        log_error "Backup container '${BACKUP_CONTAINER}' is not running"
        return 1
    fi
}

test_backup_script_exists() {
    log_info "Testing if backup script exists in container..."
    run_test
    
    if podman exec "${BACKUP_CONTAINER}" test -f "${BACKUP_SCRIPT}"; then
        log_success "Backup script exists at '${BACKUP_SCRIPT}'"
        return 0
    else
        log_error "Backup script not found at '${BACKUP_SCRIPT}'"
        return 1
    fi
}

test_backup_configuration() {
    log_info "Testing backup configuration..."
    run_test
    
    local config_output
    if config_output=$(podman exec "${BACKUP_CONTAINER}" cat /etc/backup/backup.yaml 2>/dev/null); then
        log_success "Backup configuration file is readable"
        
        # Extract configured hosts
        local hosts
        hosts=$(echo "$config_output" | grep -E "^\s*[a-zA-Z0-9_-]+:" | sed 's/://' | sed 's/^[[:space:]]*//' | grep -v "^backup_config$" || true)
        
        if [[ -n "$hosts" ]]; then
            log_info "Configured backup hosts:"
            echo "$hosts" | while read -r host; do
                [[ -n "$host" ]] && echo "  - $host"
            done
        else
            log_warning "No backup hosts found in configuration"
        fi
        
        return 0
    else
        log_error "Cannot read backup configuration file"
        return 1
    fi
}

test_verify_hosts() {
    log_info "Testing host verification using --verify-hosts..."
    run_test
    
    local verify_output
    local exit_code
    
    # Run the verify-hosts command and capture both output and exit code
    set +e
    verify_output=$(podman exec "${BACKUP_CONTAINER}" "${BACKUP_SCRIPT}" --verify-hosts 2>&1)
    exit_code=$?
    set -e
    
    log_info "Verify hosts output:"
    echo "$verify_output" | sed 's/^/  /'
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Host verification completed successfully (exit code: $exit_code)"
        
        # Check for specific success indicators in the output
        if echo "$verify_output" | grep -q "Successfully connected to"; then
            local connected_hosts
            connected_hosts=$(echo "$verify_output" | grep "Successfully connected to" | wc -l)
            print_info "Successfully connected to $connected_hosts host(s)"
        fi
        
        # Check for any failed connections
        if echo "$verify_output" | grep -q "Failed to connect\|Connection failed\|error"; then
            log_warning "Some connection warnings/errors detected in output"
        fi
        
        return 0
    else
        log_error "Host verification failed (exit code: $exit_code)"
        return 1
    fi
}

test_individual_client_connectivity() {
    log_info "Testing individual client container connectivity..."
    run_test
    
    # Test connectivity to each expected client
    local clients=("backup-client1" "backup-client2" "backup-client3")
    local all_clients_reachable=true
    
    for client in "${clients[@]}"; do
        log_info "Testing connectivity to $client..."
        
        if podman ps --format "{{.Names}}" | grep -q "^${client}$"; then
            print_info "Container '$client' is running"
            
            # Test network connectivity
            if podman exec "${BACKUP_CONTAINER}" ping -c 1 -W 2 "$client" >/dev/null 2>&1; then
                print_info "Network connectivity to '$client' successful"
            else
                print_info "Network connectivity to '$client' failed"
                all_clients_reachable=false
            fi
        else
            print_info "Container '$client' is not running"
            all_clients_reachable=false
        fi
    done
    
    if $all_clients_reachable; then
        log_success "All expected client containers are reachable"
        return 0
    else
        log_error "Some client containers are not reachable"
        return 1
    fi
}

# Main test execution
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                    BACKUP SYSTEM CONNECTIVITY TEST                     "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log_info "Starting connectivity tests for backup system..."
[INFO] Test message
    echo ""
    
    # Run all tests
    test_container_running || exit 1
    echo ""
    
    test_backup_script_exists || exit 1
    echo ""
    
    test_backup_configuration
    echo ""
    
    test_individual_client_connectivity
    echo ""
    
    test_verify_hosts
    echo ""
    
    # Print summary
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                           TEST SUMMARY                                "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Use library function for summary
    if print_test_summary "$SCRIPT_NAME"; then
        echo ""
        log_info "The backup system is ready for multi-client backup operations."
        exit 0
    else
        echo ""
        log_info "Please check the failed tests above and resolve connectivity issues."
        exit 1
    fi
}

# Run the tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
