#!/bin/bash
# Master Test Orchestrator for Backup System
# Runs all test suites in sequence and provides comprehensive reporting

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$(dirname "$TEST_DIR")"
REPORT_DIR="/tmp/backup-test-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FULL_REPORT="$REPORT_DIR/full_test_report_$TIMESTAMP.txt"

# Test suite definitions
declare -A TEST_SUITES=(
    ["environment"]="$TEST_DIR/test_environment.sh"
    ["connectivity"]="$TEST_DIR/test_connectivity.sh"
    ["help"]="$TEST_DIR/test_help_functionality.sh"
    ["runid_simple"]="$TEST_DIR/test_runid_simple.sh"
    ["runid"]="$TEST_DIR/test_runid.sh"
    ["performance"]="$TEST_DIR/test_performance.sh"
)

# Results tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=()
SUITE_RESULTS=()

# Test orchestration functions

# Initialize test environment
init_test_environment() {
    print_header "Initializing Test Environment"
    
    # Create report directory
    mkdir -p "$REPORT_DIR"
    
    # Initialize report file
    cat > "$FULL_REPORT" << EOF
BACKUP SYSTEM COMPREHENSIVE TEST REPORT
========================================
Generated: $(date)
Test Directory: $TEST_DIR
Backup Directory: $BACKUP_DIR

EOF
    
    # Check prerequisites
    print_info "Checking test prerequisites..."
    
    # Check if backup scripts exist
    if [[ ! -f "$BACKUP_DIR/backup-new.sh" ]]; then
        log_error "backup-new.sh not found in $BACKUP_DIR"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_DIR/backup-metrics" ]]; then
        log_error "backup-metrics not found in $BACKUP_DIR"
        exit 1
    fi
    
    # Check if test scripts exist
    for suite_name in "${!TEST_SUITES[@]}"; do
        local script="${TEST_SUITES[$suite_name]}"
        if [[ ! -f "$script" ]]; then
            log_error "Test script not found: $script"
            exit 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_error "Test script not executable: $script"
            exit 1
        fi
    done
    
    # Check system requirements
    if ! command -v rsync >/dev/null 2>&1; then
        print_warning "rsync not found - some tests may fail"
    fi
    
    if ! command -v journalctl >/dev/null 2>&1; then
        print_warning "journalctl not found - metrics tests may fail"
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        print_warning "bc calculator not found - performance tests may fail"
    fi
    
    log_success "Test environment initialized"
    
    # Log environment info
    {
        echo "ENVIRONMENT INFORMATION"
        echo "======================="
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "Date: $(date)"
        echo "Kernel: $(uname -a)"
        echo "Shell: $SHELL"
        echo ""
        echo "Available Test Suites:"
        for suite in "${!TEST_SUITES[@]}"; do
            echo "  - $suite: ${TEST_SUITES[$suite]}"
        done
        echo ""
    } >> "$FULL_REPORT"
}

# Run a single test suite
run_test_suite() {
    local suite_name="$1"
    local script="${TEST_SUITES[$suite_name]}"
    local suite_report="$REPORT_DIR/${suite_name}_report_$TIMESTAMP.txt"
    
    print_header "Running Test Suite: $suite_name"
    print_info "Script: $script"
    print_info "Report: $suite_report"
    
    ((TOTAL_SUITES++))
    
    # Run the test suite and capture output
    local start_time end_time duration
    start_time=$(date +%s)
    
    echo "Running test suite: $suite_name" >> "$FULL_REPORT"
    echo "Script: $script" >> "$FULL_REPORT"
    echo "Started: $(date)" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
    
    if "$script" > "$suite_report" 2>&1; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_success "Test suite '$suite_name' passed (${duration}s)"
        ((PASSED_SUITES++))
        SUITE_RESULTS+=("PASS: $suite_name (${duration}s)")
        
        echo "Result: PASSED" >> "$FULL_REPORT"
        echo "Duration: ${duration}s" >> "$FULL_REPORT"
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_error "Test suite '$suite_name' failed (${duration}s)"
        FAILED_SUITES+=("$suite_name")
        SUITE_RESULTS+=("FAIL: $suite_name (${duration}s)")
        
        echo "Result: FAILED" >> "$FULL_REPORT"
        echo "Duration: ${duration}s" >> "$FULL_REPORT"
        
        # Show last few lines of output for quick diagnosis
        print_info "Last few lines of output:"
        tail -10 "$suite_report" | sed 's/^/  /'
    fi
    
    echo "Completed: $(date)" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
    
    # Append suite report to full report
    echo "=== DETAILED OUTPUT ===" >> "$FULL_REPORT"
    cat "$suite_report" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
    echo "========================" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
}

# Generate final report
generate_final_report() {
    print_header "Generating Final Report"
    
    local total_duration
    total_duration=$(grep "Duration:" "$FULL_REPORT" | awk '{sum += $2} END {print sum}')
    
    # Add summary to report
    {
        echo ""
        echo "FINAL TEST SUMMARY"
        echo "=================="
        echo "Total Suites Run: $TOTAL_SUITES"
        echo "Passed: $PASSED_SUITES"
        echo "Failed: $((TOTAL_SUITES - PASSED_SUITES))"
        echo "Total Duration: ${total_duration:-0}s"
        echo ""
        echo "SUITE RESULTS:"
        for result in "${SUITE_RESULTS[@]}"; do
            echo "  $result"
        done
        echo ""
        
        if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
            echo "FAILED SUITES:"
            for failed in "${FAILED_SUITES[@]}"; do
                echo "  - $failed"
            done
            echo ""
        fi
        
        echo "Report generated: $(date)"
    } >> "$FULL_REPORT"
    
    log_success "Full report saved to: $FULL_REPORT"
}

# Display final results
display_final_results() {
    print_header "Final Test Results"
    
    echo -e "${WHITE}Test Summary:${NC}"
    echo -e "  Total Suites: ${WHITE}$TOTAL_SUITES${NC}"
    echo -e "  Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "  Failed: ${RED}$((TOTAL_SUITES - PASSED_SUITES))${NC}"
    echo
    
    echo -e "${WHITE}Suite Results:${NC}"
    for result in "${SUITE_RESULTS[@]}"; do
        if [[ "$result" =~ ^PASS ]]; then
            echo -e "  ${GREEN}$result${NC}"
        else
            echo -e "  ${RED}$result${NC}"
        fi
    done
    echo
    
    if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
        echo -e "${RED}Failed Suites:${NC}"
        for failed in "${FAILED_SUITES[@]}"; do
            echo -e "  ${RED}• $failed${NC}"
        done
        echo
        
        print_info "Check individual reports in: $REPORT_DIR"
        print_info "Full report available at: $FULL_REPORT"
        
        return 1
    else
        log_success "All test suites passed!"
        print_info "Full report available at: $FULL_REPORT"
        return 0
    fi
}

# Cleanup test artifacts
cleanup_test_artifacts() {
    print_header "Cleaning Up Test Artifacts"
    
    # Remove temporary test files but keep reports
    find /tmp -name "backup-*test*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /tmp -name "*backup*test*" -type f -delete 2>/dev/null || true
    find /tmp -name "runid-*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /tmp -name "*.lock" -path "/tmp/*backup*" -delete 2>/dev/null || true
    
    log_success "Test artifacts cleaned up"
}

# Show help
show_help() {
    cat << EOF
BACKUP SYSTEM TEST ORCHESTRATOR

Usage: $0 [options] [suites...]

Options:
  --help, -h          Show this help message
  --list-suites       List available test suites
  --quick             Run only quick tests (skip performance tests)
  --cleanup-only      Only cleanup test artifacts
  --no-cleanup        Don't cleanup after tests
  --report-dir DIR    Custom directory for reports (default: /tmp/backup-test-reports)

Test Suites:
  comprehensive       Full functionality tests
  runid               Run ID generation and tracking tests  
  performance         Performance and stress tests
  all                 Run all test suites (default)

Examples:
  $0                  Run all test suites
  $0 comprehensive    Run only comprehensive tests
  $0 runid performance Run run ID and performance tests
  $0 --quick          Run quick tests only
  
Report files are saved to: $REPORT_DIR
EOF
}

# Parse command line arguments
parse_arguments() {
    local suites_to_run=()
    local no_cleanup=false
    local cleanup_only=false
    local quick_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --list-suites)
                echo "Available test suites:"
                for suite in "${!TEST_SUITES[@]}"; do
                    echo "  - $suite"
                done
                exit 0
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            --cleanup-only)
                cleanup_only=true
                shift
                ;;
            --no-cleanup)
                no_cleanup=true
                shift
                ;;
            --report-dir)
                REPORT_DIR="$2"
                FULL_REPORT="$REPORT_DIR/full_test_report_$TIMESTAMP.txt"
                shift 2
                ;;
            all)
                suites_to_run=(${!TEST_SUITES[@]})
                shift
                ;;
            comprehensive|runid|performance)
                suites_to_run+=("$1")
                shift
                ;;
            *)
                echo "Error: Unknown option or suite: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Handle special modes
    if [[ "$cleanup_only" == "true" ]]; then
        cleanup_test_artifacts
        exit 0
    fi
    
    # Default to all suites if none specified
    if [[ ${#suites_to_run[@]} -eq 0 ]]; then
        if [[ "$quick_mode" == "true" ]]; then
            suites_to_run=("comprehensive" "runid")
        else
            suites_to_run=(${!TEST_SUITES[@]})
        fi
    fi
    
    # Remove performance tests in quick mode
    if [[ "$quick_mode" == "true" ]]; then
        local filtered_suites=()
        for suite in "${suites_to_run[@]}"; do
            if [[ "$suite" != "performance" ]]; then
                filtered_suites+=("$suite")
            fi
        done
        suites_to_run=("${filtered_suites[@]}")
    fi
    
    # Export variables for main function
    SUITES_TO_RUN=("${suites_to_run[@]}")
    NO_CLEANUP="$no_cleanup"
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Show banner
    print_banner
    echo -e "${WHITE}Backup System Comprehensive Test Suite${NC}"
    echo -e "Running suites: ${YELLOW}${SUITES_TO_RUN[*]}${NC}"
    echo -e "Report directory: ${BLUE}$REPORT_DIR${NC}"
    echo
    
    # Initialize
    init_test_environment
    
    # Run selected test suites
    for suite in "${SUITES_TO_RUN[@]}"; do
        if [[ -n "${TEST_SUITES[$suite]}" ]]; then
            run_test_suite "$suite"
        else
            log_error "Unknown test suite: $suite"
            exit 1
        fi
    done
    
    # Generate reports
    generate_final_report
    
    # Show results
    if display_final_results; then
        local exit_code=0
    else
        local exit_code=1
    fi
    
    # Cleanup if requested
    if [[ "$NO_CLEANUP" != "true" ]]; then
        cleanup_test_artifacts
    fi
    
    echo
    print_info "Test orchestration complete!"
    print_info "Reports available in: $REPORT_DIR"
    
    exit $exit_code
}

# Execute main function with all arguments
main "$@"
