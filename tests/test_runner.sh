#!/bin/bash
# Comprehensive Test Suite for Backup System
# Tests backup-new.sh and backup-metrics scripts

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
BACKUP_SCRIPT="$(dirname "$(dirname "$(realpath "$0")")")/backup-new.sh"
METRICS_SCRIPT="$(dirname "$(dirname "$(realpath "$0")")")/backup-metrics"
TEST_CONFIG_DIR="/tmp/backup-test-config"
TEST_BACKUP_DIR="/tmp/backup-test-data"
TEST_LOG_FILE="/tmp/test-backup.log"
TEST_STATS_LOG="/tmp/test-backup-stats.log"

# Setup test environment
setup_test_environment() {
    print_test_header "Setting up test environment"
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    mkdir -p "/tmp/test-source-data"
    
    # Create test source data
    echo "Test file 1" > "/tmp/test-source-data/file1.txt"
    echo "Test file 2" > "/tmp/test-source-data/file2.txt"
    mkdir -p "/tmp/test-source-data/subdir"
    echo "Subdirectory file" > "/tmp/test-source-data/subdir/file3.txt"
    
    # Create test configuration
    cat > "$TEST_CONFIG_DIR/backup.yaml" << 'EOF'
backup_base: "/tmp/backup-test-data/"
lock_file: "/tmp/backup-test.lock"
rsync_options: "-avz --stats --human-readable --progress --delete"

hosts:
  localhost:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/test-source-data"
        dest_subdir: "test-data"
      - path: "/tmp/test-source-data/file1.txt" 
        dest_subdir: "system"

snapshots:
  volume: "/tmp"
  schedules:
    - name: "test-snapshot"
      keep: 1
      source: "/tmp/test-source-data"
      destination: "/tmp/test-snapshots"
EOF

    cat > "$TEST_CONFIG_DIR/influxdb-config.yaml" << 'EOF'
influxdb:
  url: "http://localhost:8086"
  token: "test-token"
  org: "test-org"
  bucket: "backup-metrics"
EOF

    # Clear any existing test logs
    rm -f "$TEST_LOG_FILE" "$TEST_STATS_LOG"
    
    print_test_success "Test environment setup completed"
}

# Cleanup test environment
cleanup_test_environment() {
    print_test_header "Cleaning up test environment"
    
    rm -rf "$TEST_CONFIG_DIR"
    rm -rf "$TEST_BACKUP_DIR"
    rm -rf "/tmp/test-source-data"
    rm -rf "/tmp/test-snapshots"
    rm -f "$TEST_LOG_FILE" "$TEST_STATS_LOG"
    rm -f "/tmp/backup-test.lock"
    
    print_test_success "Test environment cleaned up"
}

# Test: Verify scripts exist and are executable
test_scripts_exist() {
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        print_test_failure "Backup script not found: $BACKUP_SCRIPT"
        return 1
    fi
    
    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        print_test_failure "Backup script not executable: $BACKUP_SCRIPT"
        return 1
    fi
    
    if [[ ! -f "$METRICS_SCRIPT" ]]; then
        print_test_failure "Metrics script not found: $METRICS_SCRIPT"
        return 1
    fi
    
    if [[ ! -x "$METRICS_SCRIPT" ]]; then
        print_test_failure "Metrics script not executable: $METRICS_SCRIPT"
        return 1
    fi
    
    return 0
}

# Test: Backup script help functionality
test_backup_help() {
    local output
    output=$("$BACKUP_SCRIPT" --help 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Backup script --help returned non-zero exit code: $exit_code"
        return 1
    fi
    
    if [[ ! "$output" =~ "Usage:" ]]; then
        print_test_failure "Backup script help output doesn't contain 'Usage:'"
        return 1
    fi
    
    return 0
}

# Test: Metrics script help functionality
test_metrics_help() {
    local output
    output=$("$METRICS_SCRIPT" --help 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Metrics script --help returned non-zero exit code: $exit_code"
        return 1
    fi
    
    if [[ ! "$output" =~ "Usage:" ]]; then
        print_test_failure "Metrics script help output doesn't contain 'Usage:'"
        return 1
    fi
    
    return 0
}

# Test: Backup script dry run functionality
test_backup_dry_run() {
    local output
    output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --dry-run 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Backup script dry run failed with exit code: $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    if [[ ! "$output" =~ "DRY RUN" ]]; then
        print_test_failure "Dry run output doesn't contain 'DRY RUN'"
        return 1
    fi
    
    if [[ ! "$output" =~ "run_id=" ]]; then
        print_test_failure "Dry run output doesn't contain run_id"
        return 1
    fi
    
    return 0
}

# Test: Backup script actual execution
test_backup_execution() {
    local output
    
    # Set up environment variable to redirect stats log to test location
    export BACKUP_STATS_LOG="/tmp/test-backup-stats.log"
    
    output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    # Clear the environment variable
    unset BACKUP_STATS_LOG
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Backup script execution failed with exit code: $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    if [[ ! "$output" =~ "run_id=" ]]; then
        print_test_failure "Backup output doesn't contain run_id"
        return 1
    fi
    
    if [[ ! "$output" =~ "BACKUP_RUN_START:" ]]; then
        print_test_failure "Backup output doesn't contain BACKUP_RUN_START"
        return 1
    fi
    
    if [[ ! "$output" =~ "BACKUP_RUN_COMPLETE:" ]]; then
        print_test_failure "Backup output doesn't contain BACKUP_RUN_COMPLETE"
        return 1
    fi
    
    # Check if backup directory was created
    if [[ ! -d "$TEST_BACKUP_DIR/localhost" ]]; then
        print_test_failure "Backup directory was not created"
        return 1
    fi
    
    # Check if files were backed up
    if [[ ! -f "$TEST_BACKUP_DIR/localhost/test-data/file1.txt" ]]; then
        print_test_failure "Test file was not backed up"
        return 1
    fi
    
    return 0
}

# Test: Run ID generation and uniqueness
test_run_id_generation() {
    local run_id1 run_id2
    
    # Extract run ID from first backup
    run_id1=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --dry-run 2>&1 | grep -o "run_id=[^ ]*" | head -1 | cut -d= -f2)
    
    if [[ -z "$run_id1" ]]; then
        print_test_failure "Could not extract run_id from first backup"
        return 1
    fi
    
    sleep 1
    
    # Extract run ID from second backup
    run_id2=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --dry-run 2>&1 | grep -o "run_id=[^ ]*" | head -1 | cut -d= -f2)
    
    if [[ -z "$run_id2" ]]; then
        print_test_failure "Could not extract run_id from second backup"
        return 1
    fi
    
    if [[ "$run_id1" == "$run_id2" ]]; then
        print_test_failure "Run IDs are not unique: $run_id1 == $run_id2"
        return 1
    fi
    
    # Verify run ID format (should be numeric)
    if [[ ! "$run_id1" =~ ^[0-9]+$ ]]; then
        print_test_failure "Run ID format is invalid: $run_id1"
        return 1
    fi
    
    return 0
}

# Test: Metrics script configuration loading
test_metrics_config_loading() {
    local output
    output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --version 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Metrics script failed to load configuration"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test: Metrics script last run functionality
test_metrics_last_run() {
    # First, create a backup to generate logs
    cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup > "$TEST_LOG_FILE" 2>&1
    
    # Wait a moment for logs to be written
    sleep 2
    
    # Test metrics script
    local output
    output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --last-run 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_failure "Metrics script --last-run failed with exit code: $exit_code"
        echo "Output: $output"
        return 1
    fi
    
    # Check if output contains expected information
    if [[ ! "$output" =~ "run_id" ]]; then
        print_test_failure "Metrics output doesn't contain run_id information"
        return 1
    fi
    
    return 0
}

# Test: Backup log format and content
test_backup_log_format() {
    # Set up environment variable for stats log
    export BACKUP_STATS_LOG="/tmp/test-backup-stats.log"
    
    # Create a backup to generate logs
    local output
    output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
    
    # Clear the environment variable
    unset BACKUP_STATS_LOG
    
    # Check for required log entries
    if [[ ! "$output" =~ "BACKUP_RUN_START:" ]]; then
        print_test_failure "Missing BACKUP_RUN_START log entry"
        return 1
    fi
    
    if [[ ! "$output" =~ "BACKUP_RUN_COMPLETE:" ]]; then
        print_test_failure "Missing BACKUP_RUN_COMPLETE log entry"
        return 1
    fi
    
    # Extract run ID and verify consistency
    local start_run_id=$(echo "$output" | grep "BACKUP_RUN_START:" | grep -o "run_id=[^ ]*" | cut -d= -f2)
    local complete_run_id=$(echo "$output" | grep "BACKUP_RUN_COMPLETE:" | grep -o "run_id=[^ ]*" | cut -d= -f2)
    
    if [[ "$start_run_id" != "$complete_run_id" ]]; then
        print_test_failure "Run ID inconsistency: start=$start_run_id, complete=$complete_run_id"
        return 1
    fi
    
    # Check timestamp format
    if [[ ! "$output" =~ timestamp=[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        print_test_failure "Invalid timestamp format in logs"
        return 1
    fi
    
    return 0
}

# Test: Error handling and recovery
test_error_handling() {
    # Create a configuration with invalid path
    cat > "$TEST_CONFIG_DIR/backup-error-test.yaml" << 'EOF'
backup_base: "/tmp/backup-test-data/"
lock_file: "/tmp/backup-test-error.lock"
rsync_options: "-avz --stats --human-readable --progress --delete"

hosts:
  errorhost:
    hostname: "nonexistent.local"
    ssh_user: "nonexistent@nonexistent.local"
    ssh_key: "/nonexistent/key"
    ignore_ping: false
    paths:
      - path: "/nonexistent/path"
        dest_subdir: "error-test"

snapshots:
  volume: "/tmp"
  schedules: []
EOF

    local output
    output=$(cd "$TEST_CONFIG_DIR" && CONFIG_FILE="backup-error-test.yaml" "$BACKUP_SCRIPT" --verify-hosts 2>&1)
    local exit_code=$?
    
    # Should fail but gracefully
    if [[ $exit_code -eq 0 ]]; then
        print_test_failure "Error handling test should have failed"
        return 1
    fi
    
    # Check if error messages are present
    if [[ ! "$output" =~ "Failed to connect" ]] && [[ ! "$output" =~ "verification failed" ]] && [[ ! "$output" =~ "No hosts are available" ]]; then
        print_test_failure "Missing expected error messages"
        return 1
    fi
    
    return 0
}

# Test: Integration between backup script and metrics script
test_integration() {
    print_test_info "Running integration test..."
    
    # Set up environment variable for stats log
    export BACKUP_STATS_LOG="/tmp/test-backup-stats.log"
    
    # Run backup to generate logs
    local backup_output
    backup_output=$(cd "$TEST_CONFIG_DIR" && "$BACKUP_SCRIPT" --backup 2>&1)
    local backup_exit_code=$?
    
    # Clear the environment variable
    unset BACKUP_STATS_LOG
    
    if [[ $backup_exit_code -ne 0 ]]; then
        print_test_failure "Integration test: backup failed"
        return 1
    fi
    
    # Extract run ID from backup
    local run_id=$(echo "$backup_output" | grep -o "run_id=[^ ]*" | head -1 | cut -d= -f2)
    
    if [[ -z "$run_id" ]]; then
        print_test_failure "Integration test: could not extract run_id"
        return 1
    fi
    
    # Wait for logs to be written
    sleep 2
    
    # Use metrics script to query the run
    local metrics_output
    metrics_output=$(cd "$TEST_CONFIG_DIR" && "$METRICS_SCRIPT" --last-run 2>&1)
    local metrics_exit_code=$?
    
    if [[ $metrics_exit_code -ne 0 ]]; then
        print_test_failure "Integration test: metrics script failed"
        return 1
    fi
    
    # Check if metrics script found the run ID
    if [[ ! "$metrics_output" =~ "$run_id" ]]; then
        print_test_failure "Integration test: metrics script didn't find run_id $run_id"
        return 1
    fi
    
    return 0
}

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    increment_tests_total
    print_test_info "Running test: $test_name"
    
    if $test_function; then
        print_test_success "$test_name"
    else
        print_test_failure "$test_name"
    fi
    echo
}

# Main test execution
main() {
    print_test_header "Backup System Comprehensive Test Suite"
    echo "Testing backup-new.sh and backup-metrics integration"
    echo "Test directory: $(pwd)"
    echo
    
    # Setup
    setup_test_environment
    
    # Run tests
    run_test "Scripts exist and are executable" test_scripts_exist
    run_test "Backup script help functionality" test_backup_help
    run_test "Metrics script help functionality" test_metrics_help
    run_test "Backup script dry run" test_backup_dry_run
    run_test "Run ID generation and uniqueness" test_run_id_generation
    run_test "Backup script execution" test_backup_execution
    run_test "Backup log format and content" test_backup_log_format
    run_test "Metrics configuration loading" test_metrics_config_loading
    run_test "Metrics last run functionality" test_metrics_last_run
    run_test "Error handling and recovery" test_error_handling
    run_test "Integration between scripts" test_integration
    
    # Cleanup
    cleanup_test_environment
    
    # Print results using library function
    if print_test_summary "Comprehensive Test Suite"; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --setup-only   Only setup test environment"
        echo "  --cleanup-only Only cleanup test environment"
        echo
        echo "This script runs a comprehensive test suite for the backup system,"
        echo "including tests for backup-new.sh and backup-metrics scripts."
        exit 0
        ;;
    "--setup-only")
        setup_test_environment
        exit 0
        ;;
    "--cleanup-only")
        cleanup_test_environment
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Error: Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
