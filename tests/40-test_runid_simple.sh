#!/bin/bash

# TEST_DESCRIPTION: Simple run ID generation and format validation
#
# test_runid_simple.sh - Simple Run ID functionality tests
#
# This script tests ONLY the run ID generation, format, and logging
# It does NOT run actual backups or require complex configurations
#

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
BACKUP_SCRIPT="$(get_backup_script_path)"
BACKUP_METRICS="$(get_metrics_script_path)"

# Test run ID format by examining the generation method in the script
test_runid_format() {
    log_info "Testing Run ID format..."
    run_test
    
    print_test_header "Testing Run ID Format"
    
    # Look for RUN_ID generation in the backup script
    local runid_line=$(grep -n "RUN_ID=" "$BACKUP_SCRIPT" | head -1)
    
    if [[ -z "$runid_line" ]]; then
        log_error "Could not find RUN_ID generation in backup script"
        return 1
    fi
    
    local line_content=$(echo "$runid_line" | cut -d: -f2-)
    print_info "Found RUN_ID generation: $line_content"
    
    # Check if it uses the expected format
    if echo "$line_content" | grep -q "time_"; then
        log_success "Run ID uses expected time-based format"
    else
        log_error "Run ID format unexpected: $line_content"
        return 1
    fi
    
    return 0
}

# Test that the backup script generates a run ID when run with --dry-run
test_runid_generation() {
    log_info "Testing Run ID generation with --dry-run..."
    run_test
    
    print_test_header "Testing Run ID Generation with --dry-run"
    
    # Create minimal test environment
    local temp_config_dir="/tmp/runid-test-$$"
    mkdir -p "$temp_config_dir"
    
    # Create minimal config that won't require actual directories
    cat > "$temp_config_dir/backup.yaml" << 'EOF'
backup_base: "/tmp/fake-backup/"
lock_file: "/tmp/fake-backup.lock"
rsync_options: "-avz --stats"

hosts:
  testhost:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/etc/hostname"
        dest_subdir: "data"
EOF

    # Run with --dry-run to avoid permission issues
    local output
    output=$(cd "$temp_config_dir" && "$BACKUP_SCRIPT" --dry-run 2>&1)
    local exit_code=$?
    
    # Clean up immediately
    rm -rf "$temp_config_dir"
    
    if [[ $exit_code -ne 0 ]]; then
        print_info "Dry run exit code: $exit_code (may be expected)"
    fi
    
    # Look for run ID generation
    local runid=$(echo "$output" | grep -o "Generated run ID: [^[:space:]]*" | sed 's/Generated run ID: //')
    
    if [[ -z "$runid" ]]; then
        log_error "No run ID generated in dry run"
        echo "Output sample: $(echo "$output" | head -5)"
        return 1
    fi
    
    # Test format (should be time_<timestamp>)
    if [[ "$runid" =~ ^time_[0-9]+$ ]]; then
        log_success "Run ID generated with correct format: $runid"
    else
        log_error "Run ID format invalid: $runid"
        return 1
    fi
    
    return 0
}

# Test run ID uniqueness by generating multiple IDs
test_runid_uniqueness() {
    print_test_header "Testing Run ID Uniqueness"
    ((TESTS_RUN++))
    
    # Create minimal test environment
    local temp_config_dir="/tmp/runid-test-$$"
    mkdir -p "$temp_config_dir"
    
    cat > "$temp_config_dir/backup.yaml" << 'EOF'
backup_base: "/tmp/fake-backup/"
lock_file: "/tmp/fake-backup.lock"
rsync_options: "-avz --stats"

hosts:
  testhost:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/etc/hostname"
        dest_subdir: "data"
EOF

    local runids=()
    
    # Generate 3 run IDs with small delays
    for i in {1..3}; do
        local output
        output=$(cd "$temp_config_dir" && "$BACKUP_SCRIPT" --dry-run 2>&1)
        local runid=$(echo "$output" | grep -o "Generated run ID: [^[:space:]]*" | sed 's/Generated run ID: //')
        
        if [[ -n "$runid" ]]; then
            runids+=("$runid")
        fi
        
        sleep 1  # Ensure different timestamps
    done
    
    # Clean up
    rm -rf "$temp_config_dir"
    
    if [[ ${#runids[@]} -lt 3 ]]; then
        log_error "Could not generate 3 run IDs (got ${#runids[@]})"
        return 1
    fi
    
    # Check uniqueness
    local unique_count=$(printf '%s\n' "${runids[@]}" | sort -u | wc -l)
    
    if [[ $unique_count -eq ${#runids[@]} ]]; then
        log_success "All run IDs are unique: ${runids[*]}"
    else
        log_error "Duplicate run IDs found: ${runids[*]}"
        return 1
    fi
    
    return 0
}

# Test metrics script basic functionality
test_metrics_script() {
    print_test_header "Testing Metrics Script Basic Functionality"
    ((TESTS_RUN++))
    
    # Test --version
    local version_output
    version_output=$("$BACKUP_METRICS" --version 2>&1)
    local version_exit_code=$?
    
    if [[ $version_exit_code -ne 0 ]]; then
        log_error "Metrics script --version failed (exit code: $version_exit_code)"
        return 1
    fi
    
    print_info "Metrics script version: $version_output"
    
    # Test --help
    local help_output
    help_output=$("$BACKUP_METRICS" --help 2>&1)
    local help_exit_code=$?
    
    if [[ $help_exit_code -ne 0 ]]; then
        log_error "Metrics script --help failed (exit code: $help_exit_code)"
        return 1
    fi
    
    # Check for expected options
    if echo "$help_output" | grep -q "\--last-run"; then
        log_success "Metrics script has --last-run option"
    else
        log_error "Metrics script missing --last-run option"
        return 1
    fi
    
    return 0
}

# Test metrics script last-run functionality
test_metrics_last_run() {
    print_test_header "Testing Metrics Script Last Run"
    ((TESTS_RUN++))
    
    # Test --last-run (may not find any runs in test environment)
    local output
    output=$("$BACKUP_METRICS" --last-run 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Metrics script --last-run failed (exit code: $exit_code)"
        echo "Output: $output"
        return 1
    fi
    
    # Check output
    if echo "$output" | grep -q "No recent backup runs found"; then
        log_success "Metrics script reports no runs found (expected in test environment)"
    elif echo "$output" | grep -q "BACKUP RUN"; then
        log_success "Metrics script found backup runs from systemd logs"
        
        # Look for run ID patterns
        if echo "$output" | grep -qE "(time_[0-9]+|run_id=)"; then
            log_success "Metrics script output contains run ID information"
        else
            print_info "Note: Metrics script output doesn't show run ID patterns (may be expected)"
        fi
    else
        log_error "Metrics script produced unexpected output"
        echo "Output: $output"
        return 1
    fi
    
    return 0
}

# Test run ID logging format by examining log parsing methods
test_runid_log_format() {
    print_test_header "Testing Run ID Log Format Implementation"
    ((TESTS_RUN++))
    
    # Look for run ID patterns in the metrics script
    local run_start_pattern=$(grep -n "BACKUP_RUN_START" "$BACKUP_METRICS" | head -1)
    local run_complete_pattern=$(grep -n "BACKUP_RUN_COMPLETE" "$BACKUP_METRICS" | head -1)
    
    if [[ -n "$run_start_pattern" ]]; then
        log_success "Metrics script recognizes BACKUP_RUN_START pattern"
    else
        log_error "Metrics script missing BACKUP_RUN_START pattern"
        return 1
    fi
    
    if [[ -n "$run_complete_pattern" ]]; then
        log_success "Metrics script recognizes BACKUP_RUN_COMPLETE pattern"
    else
        log_error "Metrics script missing BACKUP_RUN_COMPLETE pattern"
        return 1
    fi
    
    # Look for run_id parsing
    if grep -q "run_id=" "$BACKUP_METRICS"; then
        log_success "Metrics script parses run_id parameter"
    else
        log_error "Metrics script doesn't parse run_id parameter"
        return 1
    fi
    
    return 0
}

# Main function to run all tests
main() {
    print_test_header "Simple Run ID Functionality Test Suite"
    echo "Testing run ID generation, format, and basic parsing without complex setup"
    echo
    
    # Check prerequisites
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        log_error "Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_METRICS" ]]; then
        log_error "Metrics script not found: $BACKUP_METRICS"
        exit 1
    fi
    
    # Set up test count
    increment_tests_total  # test_runid_format
    increment_tests_total  # test_runid_generation
    increment_tests_total  # test_runid_uniqueness
    increment_tests_total  # test_metrics_script
    increment_tests_total  # test_metrics_last_run
    increment_tests_total  # test_runid_log_format
    
    # Run tests
    test_runid_format || true
    test_runid_generation || true
    test_runid_uniqueness || true
    test_metrics_script || true
    test_metrics_last_run || true
    test_runid_log_format || true
    
    # Results
    echo
    print_test_summary "Simple Run ID Test"
}

# Handle arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0"
        echo
        echo "Simple Run ID Functionality Test Suite"
        echo "Tests run ID generation, format, and basic parsing without complex setup"
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
