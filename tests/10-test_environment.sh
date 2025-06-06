#!/bin/bash

# TEST_DESCRIPTION: Environment and prerequisite validation
# Test script for verifying the backup system environment
# Checks that containers are running, scripts exist and are executable, etc.

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
SCRIPT_NAME="test_environment.sh"
BACKUP_CONTAINER="backup-test"
BACKUP_SCRIPT="/opt/backup/backup-new.sh"
METRICS_SCRIPT="/opt/backup/backup-metrics"

# Additional expected containers
EXPECTED_CONTAINERS=("backup-influxdb" "backup-grafana")

# Function to get all defined client containers
get_expected_clients() {
    local clients=()
    # Get all backup-client containers that exist (created or running)
    while IFS= read -r container_name; do
        [[ -n "$container_name" ]] && clients+=("$container_name")
    done < <(podman ps -a --filter name=backup-client --format "{{.Names}}" | sort)
    echo "${clients[@]}"
}

# Get expected clients dynamically
EXPECTED_CLIENTS=($(get_expected_clients))

# Test 1: Check if backup container is running
test_backup_container_running() {
    log_info "Testing if backup container is running..."
    run_test
    
    if check_container_running "$BACKUP_CONTAINER"; then
        log_success "Backup container '$BACKUP_CONTAINER' is running"
        return 0
    else
        log_error "Backup container '$BACKUP_CONTAINER' is not running"
        return 1
    fi
}

# Test 2: Check if all client containers are running
test_client_containers_running() {
    log_info "Testing if all client containers are running..."
    log_info "Expected clients: ${EXPECTED_CLIENTS[*]}"
    run_test
    
    local all_running=true
    local running_clients=()
    local missing_clients=()
    
    for client in "${EXPECTED_CLIENTS[@]}"; do
        if check_container_running "$client"; then
            running_clients+=("$client")
            print_info "✓ Container '$client' is running"
        else
            missing_clients+=("$client")
            print_info "✗ Container '$client' is not running"
            all_running=false
        fi
    done
    
    if $all_running; then
        log_success "All ${#EXPECTED_CLIENTS[@]} client containers are running: ${running_clients[*]}"
        return 0
    else
        log_warning "Some client containers are missing: ${missing_clients[*]}"
        log_info "Running clients: ${running_clients[*]}"
        # Don't fail the test if some clients are not running - this might be expected
        return 0
    fi
}

# Test 3: Check if supporting containers are running
test_supporting_containers_running() {
    log_info "Testing if supporting containers are running..."
    run_test
    
    local all_running=true
    local running_containers=()
    local missing_containers=()
    
    for container in "${EXPECTED_CONTAINERS[@]}"; do
        if check_container_running "$container"; then
            running_containers+=("$container")
            print_info "✓ Container '$container' is running"
        else
            missing_containers+=("$container")
            print_info "✗ Container '$container' is not running"
            all_running=false
        fi
    done
    
    if $all_running; then
        log_success "All ${#EXPECTED_CONTAINERS[@]} supporting containers are running: ${running_containers[*]}"
        return 0
    else
        log_warning "Some supporting containers are not running: ${missing_containers[*]}"
        # Return success even if supporting containers are missing (they're optional for basic tests)
        return 0
    fi
}

# Test 4: Check if backup script exists and is executable
test_backup_script_accessibility() {
    log_info "Testing backup script accessibility..."
    run_test
    
    if run_in_container "$BACKUP_CONTAINER" "test -f '$BACKUP_SCRIPT'"; then
        print_info "✓ Backup script exists at '$BACKUP_SCRIPT'"
        
        if run_in_container "$BACKUP_CONTAINER" "test -x '$BACKUP_SCRIPT'"; then
            log_success "Backup script exists and is executable"
            return 0
        else
            log_error "Backup script exists but is not executable"
            return 1
        fi
    else
        log_error "Backup script not found at '$BACKUP_SCRIPT'"
        return 1
    fi
}

# Test 5: Check if metrics script exists and is executable
test_metrics_script_accessibility() {
    log_info "Testing metrics script accessibility..."
    run_test
    
    if run_in_container "$BACKUP_CONTAINER" "test -f '$METRICS_SCRIPT'"; then
        print_info "✓ Metrics script exists at '$METRICS_SCRIPT'"
        
        if run_in_container "$BACKUP_CONTAINER" "test -x '$METRICS_SCRIPT'"; then
            log_success "Metrics script exists and is executable"
            return 0
        else
            log_error "Metrics script exists but is not executable"
            return 1
        fi
    else
        log_error "Metrics script not found at '$METRICS_SCRIPT'"
        return 1
    fi
}

# Test 6: Check backup configuration file
test_backup_configuration_file() {
    log_info "Testing backup configuration file..."
    run_test
    
    local config_file="/etc/backup/backup.yaml"
    
    if run_in_container "$BACKUP_CONTAINER" "test -f '$config_file'"; then
        print_info "✓ Configuration file exists at '$config_file'"
        
        if run_in_container "$BACKUP_CONTAINER" "test -r '$config_file'"; then
            log_success "Backup configuration file is accessible"
            return 0
        else
            log_error "Configuration file exists but is not readable"
            return 1
        fi
    else
        log_error "Configuration file not found at '$config_file'"
        return 1
    fi
}

# Test 7: Check SSH key accessibility
test_ssh_key_accessibility() {
    log_info "Testing SSH key accessibility..."
    run_test
    
    local ssh_key_path="/shared/ssh-keys/backup_key"
    
    if run_in_container "$BACKUP_CONTAINER" "test -f '$ssh_key_path'"; then
        print_info "✓ SSH key exists at '$ssh_key_path'"
        
        if run_in_container "$BACKUP_CONTAINER" "test -r '$ssh_key_path'"; then
            # Check permissions (should be 600 or 400)
            local perms=$(run_in_container "$BACKUP_CONTAINER" "stat -c '%a' '$ssh_key_path'")
            if [[ "$perms" == "600" || "$perms" == "400" ]]; then
                log_success "SSH key is accessible with correct permissions ($perms)"
                return 0
            else
                log_warning "SSH key has unusual permissions ($perms), but is readable"
                return 0
            fi
        else
            log_error "SSH key exists but is not readable"
            return 1
        fi
    else
        log_error "SSH key not found at '$ssh_key_path'"
        return 1
    fi
}

# Test 8: Check network connectivity between backup and client containers
test_container_network_connectivity() {
    log_info "Testing network connectivity between containers..."
    run_test
    
    local connectivity_failures=0
    local total_tests=0
    
    for client in "${EXPECTED_CLIENTS[@]}"; do
        if check_container_running "$client"; then
            total_tests=$((total_tests + 1))
            if run_in_container "$BACKUP_CONTAINER" "ping -c 1 -W 2 '$client' >/dev/null 2>&1"; then
                print_info "✓ Network connectivity to '$client' successful"
            else
                print_info "✗ Network connectivity to '$client' failed"
                connectivity_failures=$((connectivity_failures + 1))
            fi
        fi
    done
    
    if [[ $connectivity_failures -eq 0 && $total_tests -gt 0 ]]; then
        log_success "Network connectivity test passed ($total_tests/$total_tests containers reachable)"
        return 0
    elif [[ $total_tests -eq 0 ]]; then
        log_warning "No client containers running to test connectivity"
        return 0
    else
        log_error "Network connectivity issues ($connectivity_failures/$total_tests failed)"
        return 1
    fi
}

# Test 9: Check required backup directories
test_backup_directories() {
    log_info "Testing backup directories..."
    run_test
    
    local backup_dirs=("/share" "/share/backup")
    local missing_dirs=()
    local accessible_dirs=()
    
    for dir in "${backup_dirs[@]}"; do
        if run_in_container "$BACKUP_CONTAINER" "test -d '$dir'"; then
            if run_in_container "$BACKUP_CONTAINER" "test -w '$dir'"; then
                accessible_dirs+=("$dir")
                print_info "✓ Directory '$dir' exists and is writable"
            else
                print_info "! Directory '$dir' exists but is not writable"
                missing_dirs+=("$dir (not writable)")
            fi
        else
            missing_dirs+=("$dir (missing)")
            print_info "✗ Directory '$dir' does not exist"
        fi
    done
    
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        log_success "All backup directories are accessible"
        return 0
    else
        log_error "Some backup directories have issues: ${missing_dirs[*]}"
        return 1
    fi
}

# Test 10: Check system dependencies in backup container
test_system_dependencies() {
    log_info "Testing system dependencies in backup container..."
    run_test
    
    local required_commands=("rsync" "ssh" "btrfs" "yq" "bash")
    local missing_commands=()
    local available_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if run_in_container "$BACKUP_CONTAINER" "command -v '$cmd' >/dev/null 2>&1"; then
            available_commands+=("$cmd")
            print_info "✓ Command '$cmd' is available"
        else
            missing_commands+=("$cmd")
            print_info "✗ Command '$cmd' is missing"
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        log_success "All required system dependencies are available"
        return 0
    else
        log_error "Missing system dependencies: ${missing_commands[*]}"
        return 1
    fi
}

# Main test execution
main() {
    print_banner "BACKUP SYSTEM ENVIRONMENT VERIFICATION"
    
    log_info "Starting environment verification tests..."
    log_info "Checking backup system prerequisites and environment setup"
    echo ""
    
    # Set up test count - we have 10 tests
    increment_tests_total  # test_backup_container_running
    increment_tests_total  # test_client_containers_running  
    increment_tests_total  # test_supporting_containers_running
    increment_tests_total  # test_backup_script_accessibility
    increment_tests_total  # test_metrics_script_accessibility
    increment_tests_total  # test_backup_configuration_file
    increment_tests_total  # test_ssh_key_accessibility
    increment_tests_total  # test_container_network_connectivity
    increment_tests_total  # test_backup_directories
    increment_tests_total  # test_system_dependencies
    
    # Run all environment tests
    test_backup_container_running || true
    echo ""
    
    test_client_containers_running || true
    echo ""
    
    test_supporting_containers_running || true
    echo ""
    
    test_backup_script_accessibility || true
    echo ""
    
    test_metrics_script_accessibility || true
    echo ""
    
    test_backup_configuration_file || true
    echo ""
    
    test_ssh_key_accessibility || true
    echo ""
    
    test_container_network_connectivity || true
    echo ""
    
    test_backup_directories || true
    echo ""
    
    test_system_dependencies || true
    echo ""
    
    # Print summary using library function
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                        ENVIRONMENT TEST SUMMARY                        "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Use library's test summary which returns exit code based on test results
    print_test_summary "$SCRIPT_NAME"
    local summary_exit_code=$?
    
    echo ""
    if [[ $summary_exit_code -eq 0 ]]; then
        log_info "Environment verification completed successfully."
        log_info "The backup system environment is properly configured and ready for testing."
    else
        log_error "Environment verification failed."
        log_info "Please resolve the issues above before running other tests."
    fi
    
    exit $summary_exit_code
}

# Run the tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
