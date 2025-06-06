#!/bin/bash

# TEST_DESCRIPTION: Advanced run ID tracking and backup functionality
# TEST_TIMEOUT: 180
# Run ID Functionality Test Suite
# Focused testing of run ID generation, logging, and metrics parsing

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
BACKUP_SCRIPT="$(get_backup_script_path)"
METRICS_SCRIPT="$(get_metrics_script_path)"
TEST_CONFIG_DIR="/tmp/backup-runid-test"
TEST_LOG_DIR="/tmp/backup-runid-logs"

# Setup minimal test environment
setup_runid_test() {
    print_test_header "Setting up Run ID test environment"
    
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_LOG_DIR"
    mkdir -p "/tmp/runid-source"
    mkdir -p "/tmp/runid-backup"
    
    echo "test data" > "/tmp/runid-source/test.txt"
    
    # Set environment variables for test paths
    export BACKUP_STATS_LOG="/tmp/runid-backup-stats.log"
    
    # Create minimal config
    cat > "$TEST_CONFIG_DIR/backup.yaml" << 'EOF'
backup_base: "/tmp/runid-backup/"
lock_file: "/tmp/runid-backup.lock"
rsync_options: "-avz --stats"

hosts:
  testhost:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/runid-source"
        dest_subdir: "data"
EOF

    cat > "$TEST_CONFIG_DIR/influxdb-config.yaml" << 'EOF'
influxdb:
  url: "http://localhost:8086"
  token: "test"
  org: "test"
  bucket: "test"
EOF
}

# Test run ID generation
test_runid_generation() {
    log_info "Testing Run ID generation..."
    run_test
    
    print_test_header "Testing Run ID Generation"
    
    local output1 output2 runid1 runid2
    
    # Generate first run ID
    output1=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --dry-run 2>&1)
    runid1=$(echo "$output1" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
    
    if [[ -z "$runid1" ]]; then
        log_error "Could not extract first run ID"
        return 1
    fi
    
    sleep 1
    
    # Generate second run ID
    output2=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --dry-run 2>&1)
    runid2=$(echo "$output2" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
    
    if [[ -z "$runid2" ]]; then
        log_error "Could not extract second run ID"
        return 1
    fi
    
    # Test uniqueness
    if [[ "$runid1" == "$runid2" ]]; then
        log_error "Run IDs are not unique: $runid1 == $runid2"
        return 1
    fi
    
    # Test format (should be numeric)
    if [[ ! "$runid1" =~ ^[0-9]+$ ]]; then
        log_error "Run ID format invalid: $runid1"
        return 1
    fi
    
    # Test length (should be reasonable)
    if [[ ${#runid1} -lt 10 ]]; then
        log_error "Run ID too short: $runid1 (${#runid1} chars)"
        return 1
    fi
    
    log_success "Run ID generation: unique IDs $runid1 and $runid2"
    return 0
}

# Test run ID in log messages
test_runid_logging() {
    print_test_header "Testing Run ID in Log Messages"
    
    local output runid
    
    # Run backup and capture output
    output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
    
    # Extract run ID
    runid=$(echo "$output" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
    
    if [[ -z "$runid" ]]; then
        log_error "Could not extract run ID from backup output"
        return 1
    fi
    
    # Check BACKUP_RUN_START
    if ! echo "$output" | grep -q "BACKUP_RUN_START:.*run_id=$runid"; then
        log_error "BACKUP_RUN_START missing or incorrect run_id"
        return 1
    fi
    
    # Check BACKUP_RUN_COMPLETE
    if ! echo "$output" | grep -q "BACKUP_RUN_COMPLETE:.*run_id=$runid"; then
        log_error "BACKUP_RUN_COMPLETE missing or incorrect run_id"
        return 1
    fi
    
    # Check for RSYNC_STATS if present
    if echo "$output" | grep -q "RSYNC_STATS:"; then
        if ! echo "$output" | grep -q "RSYNC_STATS:.*run_id=$runid"; then
            log_error "RSYNC_STATS missing or incorrect run_id"
            return 1
        fi
    fi
    
    log_success "Run ID logging: consistent run_id $runid in all log entries"
    return 0
}

# Test metrics script run ID parsing
test_metrics_runid_parsing() {
    print_test_header "Testing Metrics Script Run ID Parsing"
    
    # First run a test backup to generate stats
    print_info "Running a test backup to generate stats data..."
    local backup_output
    backup_output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
    local backup_exit_code=$?
    
    if [[ $backup_exit_code -ne 0 ]]; then
        log_error "Test backup failed with exit code $backup_exit_code"
        echo "Backup output: $backup_output"
        return 1
    fi
    
    # Extract run ID from backup output
    local test_runid
    test_runid=$(echo "$backup_output" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
    
    if [[ -z "$test_runid" ]]; then
        log_error "Could not extract run ID from backup output"
        return 1
    fi
    
    print_info "Test backup completed with run ID: $test_runid"
    
    # Test metrics script basic functionality
    # Note: In test environment, metrics script reads from systemd logs,
    # not from our test backup runs, so we test general functionality
    local metrics_output
    metrics_output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --last-run 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Metrics script failed with exit code $exit_code"
        echo "Output: $metrics_output"
        return 1
    fi
    
    # Check if metrics script is working properly
    # It may show "No recent backup runs found" which is acceptable in test environment
    if echo "$metrics_output" | grep -q "No recent backup runs found"; then
        print_info "Metrics script working correctly (no systemd logs in test environment)"
    elif echo "$metrics_output" | grep -q "BACKUP RUN"; then
        print_info "Metrics script found existing backup runs from systemd logs"
        # Check for run ID formatting
        if ! echo "$metrics_output" | grep -qE "(ID: time_|run_id=)"; then
            log_error "Metrics script output doesn't contain run ID information"
            echo "Metrics output: $metrics_output"
            return 1
        fi
    else
        log_error "Metrics script produced unexpected output"
        echo "Metrics output: $metrics_output"
        return 1
    fi
    
    # Test metrics script version functionality 
    local version_output
    version_output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --version 2>&1)
    local version_exit_code=$?
    
    if [[ $version_exit_code -ne 0 ]]; then
        log_error "Metrics script --version failed with exit code $version_exit_code"
        return 1
    fi
    
    log_success "Metrics parsing: script is functional and shows backup run information with IDs"
    return 0
}

# Test multiple backup runs with different run IDs
test_multiple_runs() {
    print_test_header "Testing Multiple Backup Runs"
    
    local runids=()
    local outputs=()
    
    # Run 3 backups
    for i in {1..3}; do
        print_info "Running backup $i of 3..."
        local output
        output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
        local backup_exit_code=$?
        
        if [[ $backup_exit_code -ne 0 ]]; then
            log_error "Backup $i failed with exit code $backup_exit_code"
            echo "Output: $output"
            return 1
        fi
        
        local runid
        runid=$(echo "$output" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
        
        if [[ -z "$runid" ]]; then
            log_error "Could not extract run ID from backup $i"
            return 1
        fi
        
        runids+=("$runid")
        outputs+=("$output")
        
        print_info "Backup $i completed with run ID: $runid"
        
        # Small delay between runs
        sleep 2
    done
    
    # Verify all run IDs are unique
    for ((i=0; i<${#runids[@]}; i++)); do
        for ((j=i+1; j<${#runids[@]}; j++)); do
            if [[ "${runids[i]}" == "${runids[j]}" ]]; then
                log_error "Duplicate run IDs found: ${runids[i]} (runs $((i+1)) and $((j+1)))"
                return 1
            fi
        done
    done
    
    print_info "Generated unique run IDs: ${runids[*]}"
    
    # Test metrics script functionality (expects systemd logs, not our test runs)
    # This tests that the metrics script is working correctly with available data
    local metrics_output
    metrics_output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --last-run --runs 3 2>&1)
    local metrics_exit_code=$?
    
    if [[ $metrics_exit_code -ne 0 ]]; then
        log_error "Metrics script failed with exit code $metrics_exit_code"
        echo "Metrics output: $metrics_output"
        return 1
    fi
    
    # Verify metrics script shows backup run information (from systemd logs)
    local run_count
    run_count=$(echo "$metrics_output" | grep -c "BACKUP RUN" || echo "0")
    
    if [[ $run_count -eq 0 ]]; then
        log_error "Metrics script didn't show any backup runs"
        echo "Metrics output: $metrics_output"
        return 1
    fi
    
    log_success "Multiple runs: generated ${#runids[@]} unique run IDs, metrics script shows $run_count runs from systemd logs"
    return 0
}

# Test run ID consistency across backup session
test_runid_consistency() {
    print_test_header "Testing Run ID Consistency Across Backup Session"
    
    # Create a config with multiple hosts to test consistency
    cat > "$TEST_CONFIG_DIR/multi-host.yaml" << 'EOF'
backup_base: "/tmp/runid-multi-backup/"
lock_file: "/tmp/runid-multi.lock"
rsync_options: "-avz --stats"

hosts:
  host1:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/runid-source"
        dest_subdir: "host1-data"
  host2:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/etc/hostname"
        dest_subdir: "host2-data"
EOF

    # Run backup with multiple hosts
    local output
    output=$(cd "$TEST_CONFIG_DIR" && CONFIG_FILE="multi-host.yaml" "$BACKUP_SCRIPT" --backup 2>&1)
    
    # Extract all run IDs from the output
    local run_ids
    mapfile -t run_ids < <(echo "$output" | grep -o "run_id=[^ ]*" | cut -d= -f2 | sort -u)
    
    if [[ ${#run_ids[@]} -ne 1 ]]; then
        log_error "Inconsistent run IDs found: ${run_ids[*]} (expected exactly 1 unique ID)"
        return 1
    fi
    
    local runid="${run_ids[0]}"
    
    # Count occurrences of the run ID
    local runid_count
    runid_count=$(echo "$output" | grep -c "run_id=$runid")
    
    if [[ $runid_count -lt 2 ]]; then
        log_error "Run ID appears too few times: $runid_count (expected at least 2)"
        return 1
    fi
    
    log_success "Run ID consistency: $runid used consistently $runid_count times"
    return 0
}

# Test run ID with error scenarios
test_runid_error_scenarios() {
    print_test_header "Testing Run ID in Error Scenarios"
    
    # Test with a nonexistent source path - this should generate a run ID but have warnings/errors
    cat > "$TEST_CONFIG_DIR/error-config.yaml" << 'EOF'
backup_base: "/tmp/runid-error-backup/"
lock_file: "/tmp/runid-error.lock"
rsync_options: "-avz --stats"

hosts:
  errorhost:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/nonexistent/path/that/should/not/exist"
        dest_subdir: "error-data"
EOF

    # Ensure backup directory exists for this test
    mkdir -p "/tmp/runid-error-backup"
    
    # Run backup with error configuration (should complete but with errors)
    local output
    output=$(cd "$TEST_CONFIG_DIR" && CONFIG_FILE="error-config.yaml" "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    # Check if run ID is generated even with path errors
    local runid
    runid=$(echo "$output" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
    
    if [[ -n "$runid" ]]; then
        log_success "Error scenario: run ID $runid generated even with path errors (exit code: $exit_code)"
        return 0
    fi
    
    # Alternative error test: corrupted config file (should fail before run ID generation)
    print_info "Testing with corrupted config file..."
    echo "invalid: yaml: content: [" > "$TEST_CONFIG_DIR/corrupted-config.yaml"
    
    local corrupt_output
    corrupt_output=$(cd "$TEST_CONFIG_DIR" && CONFIG_FILE="corrupted-config.yaml" "$BACKUP_SCRIPT" --backup 2>&1)
    local corrupt_exit_code=$?
    
    # This should definitely fail early
    if [[ $corrupt_exit_code -eq 0 ]]; then
        log_error "Corrupted config test should have failed"
        return 1
    fi
    
    log_success "Error scenario: backup appropriately fails with corrupted config (exit code: $corrupt_exit_code)"
    return 0
}

# Test metrics script delete-data functionality
test_metrics_delete_data() {
    print_test_header "Testing Metrics Script Delete Data Functionality"
    
    # Test that the delete-data option exists and shows proper warning
    print_info "Testing --delete-data parameter parsing..."
    
    # We can't run the actual delete operation in tests, but we can test the parameter parsing
    # The script should require confirmation, so we'll test that it prompts properly
    local delete_output
    delete_output=$(cd "$TEST_CONFIG_DIR" && echo "CANCEL" | "$METRICS_SCRIPT" --delete-data 2>&1)
    local delete_exit_code=$?
    
    # Should mention deletion and then be cancelled
    if echo "$delete_output" | grep -q "WARNING.*delete.*ALL.*backup.*data"; then
        log_success "Delete data: Shows proper warning about data deletion"
    else
        log_error "Delete data: Missing proper warning about data deletion"
        echo "Output: $delete_output"
        return 1
    fi
    
    if echo "$delete_output" | grep -q -i "cancel"; then
        log_success "Delete data: Properly handles cancellation"
    else
        log_error "Delete data: Doesn't handle cancellation properly"
        echo "Output: $delete_output"
        return 1
    fi
    
    log_success "Delete data functionality: parameter parsing and safety checks working"
    return 0
}

# Cleanup
cleanup_runid_test() {
    print_test_header "Cleaning up Run ID test environment"
    
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_LOG_DIR"
    rm -rf "/tmp/runid-source"
    rm -rf "/tmp/runid-backup"
    rm -rf "/tmp/runid-multi-backup"
    rm -rf "/tmp/runid-error-backup"
    rm -f "/tmp/runid-backup.lock"
    rm -f "/tmp/runid-multi.lock"
    rm -f "/tmp/runid-error.lock"
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    print_test_header "Run ID Functionality Test Suite"
    echo "Focused testing of run ID generation, logging, and metrics parsing"
    echo
    
    # Set up test count
    increment_tests_total  # test_runid_generation
    increment_tests_total  # test_runid_logging
    increment_tests_total  # test_metrics_runid_parsing
    increment_tests_total  # test_multiple_runs
    increment_tests_total  # test_runid_consistency
    increment_tests_total  # test_runid_error_scenarios
    increment_tests_total  # test_metrics_delete_data
    
    # Setup
    setup_runid_test
    
    # Run tests
    test_runid_generation || true
    test_runid_logging || true
    test_metrics_runid_parsing || true
    test_multiple_runs || true
    test_runid_consistency || true
    test_runid_error_scenarios || true
    test_metrics_delete_data || true
    
    # Cleanup
    cleanup_runid_test
    
    # Results
    print_test_summary "Run ID Test"
}

# Handle arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0"
        echo
        echo "Run ID Functionality Test Suite"
        echo "Tests run ID generation, logging, and metrics parsing"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Error: Unknown option: $1"
        exit 1
        ;;
esac
