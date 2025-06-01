#!/bin/bash

#
# test_runid_simple.sh - Simple Run ID functionality tests
#
# This script tests ONLY the run ID generation, format, and logging
# It does NOT run actual backups or require complex configurations
#

# Test configuration
BACKUP_SCRIPT="$(dirname "$(dirname "$(realpath "$0")")")/backup-new.sh"
BACKUP_METRICS="$(dirname "$(dirname "$(realpath "$0")")")/backup-metrics"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Global test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test run ID format by examining the generation method in the script
test_runid_format() {
    print_test_header "Testing Run ID Format"
    ((TESTS_RUN++))
    
    # Look for RUN_ID generation in the backup script
    local runid_line=$(grep -n "RUN_ID=" "$BACKUP_SCRIPT" | head -1)
    
    if [[ -z "$runid_line" ]]; then
        print_failure "Could not find RUN_ID generation in backup script"
        return 1
    fi
    
    local line_content=$(echo "$runid_line" | cut -d: -f2-)
    print_info "Found RUN_ID generation: $line_content"
    
    # Check if it uses the expected format
    if echo "$line_content" | grep -q "time_"; then
        print_success "Run ID uses expected time-based format"
    else
        print_failure "Run ID format unexpected: $line_content"
        return 1
    fi
    
    return 0
}

# Test that the backup script generates a run ID when run with --dry-run
test_runid_generation() {
    print_test_header "Testing Run ID Generation with --dry-run"
    ((TESTS_RUN++))
    
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
        print_failure "No run ID generated in dry run"
        echo "Output sample: $(echo "$output" | head -5)"
        return 1
    fi
    
    # Test format (should be time_<timestamp>)
    if [[ "$runid" =~ ^time_[0-9]+$ ]]; then
        print_success "Run ID generated with correct format: $runid"
    else
        print_failure "Run ID format invalid: $runid"
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
        print_failure "Could not generate 3 run IDs (got ${#runids[@]})"
        return 1
    fi
    
    # Check uniqueness
    local unique_count=$(printf '%s\n' "${runids[@]}" | sort -u | wc -l)
    
    if [[ $unique_count -eq ${#runids[@]} ]]; then
        print_success "All run IDs are unique: ${runids[*]}"
    else
        print_failure "Duplicate run IDs found: ${runids[*]}"
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
        print_failure "Metrics script --version failed (exit code: $version_exit_code)"
        return 1
    fi
    
    print_info "Metrics script version: $version_output"
    
    # Test --help
    local help_output
    help_output=$("$BACKUP_METRICS" --help 2>&1)
    local help_exit_code=$?
    
    if [[ $help_exit_code -ne 0 ]]; then
        print_failure "Metrics script --help failed (exit code: $help_exit_code)"
        return 1
    fi
    
    # Check for expected options
    if echo "$help_output" | grep -q "\--last-run"; then
        print_success "Metrics script has --last-run option"
    else
        print_failure "Metrics script missing --last-run option"
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
        print_failure "Metrics script --last-run failed (exit code: $exit_code)"
        echo "Output: $output"
        return 1
    fi
    
    # Check output
    if echo "$output" | grep -q "No recent backup runs found"; then
        print_success "Metrics script reports no runs found (expected in test environment)"
    elif echo "$output" | grep -q "BACKUP RUN"; then
        print_success "Metrics script found backup runs from systemd logs"
        
        # Look for run ID patterns
        if echo "$output" | grep -qE "(time_[0-9]+|run_id=)"; then
            print_success "Metrics script output contains run ID information"
        else
            print_info "Note: Metrics script output doesn't show run ID patterns (may be expected)"
        fi
    else
        print_failure "Metrics script produced unexpected output"
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
        print_success "Metrics script recognizes BACKUP_RUN_START pattern"
    else
        print_failure "Metrics script missing BACKUP_RUN_START pattern"
        return 1
    fi
    
    if [[ -n "$run_complete_pattern" ]]; then
        print_success "Metrics script recognizes BACKUP_RUN_COMPLETE pattern"
    else
        print_failure "Metrics script missing BACKUP_RUN_COMPLETE pattern"
        return 1
    fi
    
    # Look for run_id parsing
    if grep -q "run_id=" "$BACKUP_METRICS"; then
        print_success "Metrics script parses run_id parameter"
    else
        print_failure "Metrics script doesn't parse run_id parameter"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    print_test_header "Simple Run ID Functionality Test Suite"
    echo "Focused testing of run ID generation, format, and basic parsing"
    echo
    
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Check that scripts exist
    if [[ ! -f "$BACKUP_SCRIPT" ]]; then
        echo -e "${RED}ERROR: Backup script not found: $BACKUP_SCRIPT${NC}"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_METRICS" ]]; then
        echo -e "${RED}ERROR: Metrics script not found: $BACKUP_METRICS${NC}"
        exit 1
    fi
    
    # Run tests
    test_runid_format
    test_runid_generation
    test_runid_uniqueness
    test_metrics_script
    test_metrics_last_run
    test_runid_log_format
    
    # Results
    echo
    print_test_header "Simple Run ID Test Results"
    echo -e "Tests run: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All run ID tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some run ID tests failed!${NC}"
        exit 1
    fi
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
