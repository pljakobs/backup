#!/bin/bash

# Test script for verifying --help functionality of backup scripts
# Tests both backup-new.sh and backup-metrics in containerized environment

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
SCRIPT_NAME="test_help_functionality.sh"
BACKUP_CONTAINER="backup-test"
BACKUP_SCRIPT="/opt/backup/backup-new.sh"
METRICS_SCRIPT="/opt/backup/backup-metrics"

# Log file
LOG_FILE="/tmp/test_help_functionality.log"

# Test 1: Check if backup container is running
test_backup_container_status() {
    print_test_header "Backup Container Status"
    
    if check_container_running "$BACKUP_CONTAINER"; then
        print_test_result "Container Status" "PASS" "Backup container '$BACKUP_CONTAINER' is running" "$LOG_FILE"
        return 0
    else
        print_test_result "Container Status" "FAIL" "Backup container '$BACKUP_CONTAINER' is not running" "$LOG_FILE"
        return 1
    fi
}

# Test 2: Test backup-new.sh --help functionality
test_backup_script_help() {
    print_test_header "Backup Script Help Functionality"
    
    local output
    local exit_code
    
    # Test --help option
    output=$(run_in_container "$BACKUP_CONTAINER" "$BACKUP_SCRIPT --help" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_result "Backup Script --help Exit Code" "FAIL" "Exit code: $exit_code"
        echo -e "${YELLOW}Output:${NC} $output"
        return 1
    fi
    
    print_test_result "Backup Script --help Exit Code" "PASS" "Exit code: 0"
    
    # Check for key elements in help output
    local tests_passed=0
    local tests_total=5
    
    if [[ "$output" =~ "Usage:" ]]; then
        print_test_result "Backup Script Help Content" "PASS" "Contains 'Usage:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Backup Script Help Content" "FAIL" "Missing 'Usage:' section"
    fi
    
    if [[ "$output" =~ "--help" ]]; then
        print_test_result "Backup Script Help Content" "PASS" "Contains '--help' option description"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Backup Script Help Content" "FAIL" "Missing '--help' option description"
    fi
    
    if [[ "$output" =~ "--dry-run" ]]; then
        print_test_result "Backup Script Help Content" "PASS" "Contains '--dry-run' option"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Backup Script Help Content" "FAIL" "Missing '--dry-run' option"
    fi
    
    if [[ "$output" =~ "--verify-hosts" ]]; then
        print_test_result "Backup Script Help Content" "PASS" "Contains '--verify-hosts' option"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Backup Script Help Content" "FAIL" "Missing '--verify-hosts' option"
    fi
    
    if [[ "$output" =~ "Examples:" ]]; then
        print_test_result "Backup Script Help Content" "PASS" "Contains 'Examples:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Backup Script Help Content" "FAIL" "Missing 'Examples:' section"
    fi
    
    # Test -h shorthand
    local short_output
    local short_exit_code
    
    short_output=$(run_in_container "$BACKUP_CONTAINER" "$BACKUP_SCRIPT -h" 2>&1) || short_exit_code=$?
    short_exit_code=${short_exit_code:-0}
    
    if [[ $short_exit_code -eq 0 ]]; then
        print_test_result "Backup Script -h Shorthand" "PASS" "Exit code: 0"
    else
        print_test_result "Backup Script -h Shorthand" "FAIL" "Exit code: $short_exit_code"
    fi
    
    # Compare outputs (should be identical)
    if [[ "$output" == "$short_output" ]]; then
        print_test_result "Backup Script Help Consistency" "PASS" "--help and -h produce identical output"
    else
        print_test_result "Backup Script Help Consistency" "FAIL" "--help and -h produce different output"
    fi
    
    echo -e "\n${CYAN}Sample of backup script help output:${NC}"
    echo "$output" | head -10
    
    return 0
}

# Test 3: Test backup-metrics --help functionality
test_metrics_script_help() {
    print_test_header "Backup Metrics Script Help Functionality"
    
    local output
    local exit_code
    
    # Test --help option
    output=$(run_in_container "$BACKUP_CONTAINER" "$METRICS_SCRIPT --help" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_result "Metrics Script --help Exit Code" "FAIL" "Exit code: $exit_code"
        echo -e "${YELLOW}Output:${NC} $output"
        return 1
    fi
    
    print_test_result "Metrics Script --help Exit Code" "PASS" "Exit code: 0"
    
    # Check for key elements in help output
    local tests_passed=0
    local tests_total=6
    
    if [[ "$output" =~ "Usage:" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains 'Usage:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing 'Usage:' section"
    fi
    
    if [[ "$output" =~ "Options:" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains 'Options:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing 'Options:' section"
    fi
    
    if [[ "$output" =~ "--status" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains '--status' option"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing '--status' option"
    fi
    
    if [[ "$output" =~ "--send-influxdb" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains '--send-influxdb' option"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing '--send-influxdb' option"
    fi
    
    if [[ "$output" =~ "Examples:" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains 'Examples:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing 'Examples:' section"
    fi
    
    if [[ "$output" =~ "Deduplication:" ]]; then
        print_test_result "Metrics Script Help Content" "PASS" "Contains 'Deduplication:' section"
        tests_passed=$((tests_passed + 1))
    else
        print_test_result "Metrics Script Help Content" "FAIL" "Missing 'Deduplication:' section"
    fi
    
    echo -e "\n${CYAN}Sample of metrics script help output:${NC}"
    echo "$output" | head -15
    
    return 0
}

# Test 4: Test script accessibility and permissions
test_script_accessibility() {
    print_test_header "Script Accessibility and Permissions"
    
    # Check if backup-new.sh exists and is executable
    if run_in_container "$BACKUP_CONTAINER" "test -x $BACKUP_SCRIPT"; then
        print_test_result "Backup Script Accessibility" "PASS" "$BACKUP_SCRIPT exists and is executable" "$LOG_FILE"
    else
        print_test_result "Backup Script Accessibility" "FAIL" "$BACKUP_SCRIPT not found or not executable" "$LOG_FILE"
    fi
    
    # Check if backup-metrics exists and is executable
    if run_in_container "$BACKUP_CONTAINER" "test -x $METRICS_SCRIPT"; then
        print_test_result "Metrics Script Accessibility" "PASS" "$METRICS_SCRIPT exists and is executable" "$LOG_FILE"
    else
        print_test_result "Metrics Script Accessibility" "FAIL" "$METRICS_SCRIPT not found or not executable" "$LOG_FILE"
    fi
    
    # Check script ownership and permissions
    local backup_perms metrics_perms
    backup_perms=$(run_in_container "$BACKUP_CONTAINER" "ls -l $BACKUP_SCRIPT" 2>/dev/null || echo "not found")
    metrics_perms=$(run_in_container "$BACKUP_CONTAINER" "ls -l $METRICS_SCRIPT" 2>/dev/null || echo "not found")
    
    echo -e "\n${CYAN}Script permissions:${NC}"
    echo "Backup script:  $backup_perms"
    echo "Metrics script: $metrics_perms"
    
    return 0
}

# Test 5: Test invalid options handling
test_invalid_options() {
    print_test_header "Invalid Options Handling"
    
    # Test backup script with invalid option
    local output exit_code
    output=$(run_in_container "$BACKUP_CONTAINER" "$BACKUP_SCRIPT --invalid-option" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_result "Backup Script Invalid Option" "PASS" "Properly rejects invalid option (exit code: $exit_code)" "$LOG_FILE"
    else
        print_test_result "Backup Script Invalid Option" "FAIL" "Accepts invalid option (exit code: $exit_code)" "$LOG_FILE"
    fi
    
    # Test metrics script with invalid option
    output=$(run_in_container "$BACKUP_CONTAINER" "$METRICS_SCRIPT --invalid-option" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    if [[ $exit_code -ne 0 ]]; then
        print_test_result "Metrics Script Invalid Option" "PASS" "Properly rejects invalid option (exit code: $exit_code)" "$LOG_FILE"
    else
        print_test_result "Metrics Script Invalid Option" "FAIL" "Accepts invalid option (exit code: $exit_code)" "$LOG_FILE"
    fi
    
    return 0
}

# Function to print final summary
print_summary() {
    echo -e "\n${BLUE}=== TEST SUMMARY ===${NC}"
    echo -e "Tests run:    ${YELLOW}$TESTS_RUN${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some tests failed!${NC}"
        echo -e "Check log file: $LOG_FILE"
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}=== BACKUP SYSTEM HELP FUNCTIONALITY TESTS ===${NC}"
    setup_test_log "$LOG_FILE" "$SCRIPT_NAME"
    
    # Run all tests
    test_backup_container_status
    test_script_accessibility
    test_backup_script_help
    test_metrics_script_help
    test_invalid_options
    
    # Print summary and exit
    print_test_summary "$SCRIPT_NAME"
    local exit_code=$?
    
    print_timestamp "Test run completed with exit code: $exit_code" >> "$LOG_FILE"
    exit $exit_code
}

# Check if running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
