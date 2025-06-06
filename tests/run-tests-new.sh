#!/bin/bash
# Test Orchestrator for Backup System
# Runs test suites individually or in groups with comprehensive reporting

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
YAML_CONFIG="$TEST_DIR/test-suites.yaml"

# Test suite definitions - loaded from YAML or fallback
declare -A SUITE_GROUPS=()
declare -A SUITE_SHORTNAMES=()
declare -A SUITE_DESCRIPTIONS=()
declare -A SHORTNAME_TO_PREFIXES=()

# Dynamic test discovery
declare -A TEST_SCRIPTS=()
declare -A TEST_DESCRIPTIONS=()
declare -A SUITE_TESTS=()
TESTS_DISCOVERED=false

# Results tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=()
SUITE_RESULTS=()

# Test orchestration functions

# YAML parser using yq for test suite configuration
parse_yaml_config() {
    local config_file="$1"
    
    # Initialize fallback values
    SUITE_GROUPS=(
        ["10"]="Environment"
        ["20"]="Connectivity"
        ["30"]="User Interface"
        ["40"]="Basic Functionality"
        ["50"]="Advanced Functionality"
        ["60"]="Performance"
        ["70"]="Metrics"
    )
    
    if [[ ! -f "$config_file" ]]; then
        print_warning "YAML config file not found: $config_file"
        print_info "Using fallback suite definitions"
        return 0
    fi
    
    # Check if yq is available
    if ! command -v yq >/dev/null 2>&1; then
        print_warning "yq not found - using fallback suite definitions"
        return 0
    fi
    
    print_info "Loading test suite configuration from: $config_file"
    
    # Clear arrays
    SUITE_GROUPS=()
    SUITE_SHORTNAMES=()
    SUITE_DESCRIPTIONS=()
    SHORTNAME_TO_PREFIXES=()
    
    # Parse YAML file using yq
    while IFS=$'\t' read -r prefix shortname description; do
        [[ -z "$prefix" || -z "$shortname" || -z "$description" ]] && continue
        
        # Convert prefix pattern to actual prefixes (e.g., "1*" -> "10")
        if [[ "$prefix" =~ ^([0-9]+)\*$ ]]; then
            local base_prefix="${BASH_REMATCH[1]}"
            local numeric_prefix="${base_prefix}0"
            
            SUITE_GROUPS["$numeric_prefix"]="$shortname"
            SUITE_SHORTNAMES["$numeric_prefix"]="$shortname"
            SUITE_DESCRIPTIONS["$numeric_prefix"]="$description"
            
            # Map shortname to prefixes
            if [[ -n "${SHORTNAME_TO_PREFIXES[$shortname]:-}" ]]; then
                SHORTNAME_TO_PREFIXES["$shortname"]+=" $numeric_prefix"
            else
                SHORTNAME_TO_PREFIXES["$shortname"]="$numeric_prefix"
            fi
        fi
    done < <(yq eval '.suites[].suite | [.prefix, .shortname, .description] | @tsv' "$config_file")
    
    local loaded_suites=${#SUITE_GROUPS[@]}
    local loaded_shortnames=${#SHORTNAME_TO_PREFIXES[@]}
    
    print_success "Loaded $loaded_suites suite definitions with $loaded_shortnames unique shortnames"
}

# Discover test scripts dynamically
discover_test_scripts() {
    # Only discover once
    if [[ "$TESTS_DISCOVERED" == "true" ]]; then
        return 0
    fi
    
    print_info "Discovering test scripts..."
    
    # Find all executable test scripts with numeric prefixes
    for script in "$TEST_DIR"/[0-9][0-9]-*.sh; do
        if [[ -f "$script" && -x "$script" ]]; then
            local basename=$(basename "$script")
            local prefix="${basename:0:2}"
            local test_name="${basename%.sh}"
            
            # Extract test description from script
            local description=""
            if grep -q "^# TEST_DESCRIPTION:" "$script"; then
                description=$(grep "^# TEST_DESCRIPTION:" "$script" | sed 's/^# TEST_DESCRIPTION: *//')
            else
                description="Test script: $test_name"
            fi
            
            # Store test information
            TEST_SCRIPTS["$test_name"]="$script"
            TEST_DESCRIPTIONS["$test_name"]="$description"
            
            # Group tests by prefix
            if [[ -n "${SUITE_GROUPS[$prefix]:-}" ]]; then
                if [[ -n "${SUITE_TESTS[$prefix]:-}" ]]; then
                    SUITE_TESTS["$prefix"]+=" $test_name"
                else
                    SUITE_TESTS["$prefix"]="$test_name"
                fi
            fi
            
            # Debug output (optional)
            # echo "DEBUG: Discovered: $test_name ($description)"
        fi
    done
    
    local total_tests=${#TEST_SCRIPTS[@]}
    local total_suites=${#SUITE_TESTS[@]}
    
    print_success "Discovered $total_tests test scripts in $total_suites test suites"
    TESTS_DISCOVERED=true
}

# Initialize test environment
init_test_environment() {
    print_header "Initializing Test Environment"
    
    # Load suite configuration from YAML
    parse_yaml_config "$YAML_CONFIG"
    
    # Discover test scripts dynamically
    discover_test_scripts
    
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
    
    # Check if discovered test scripts are executable
    for test_name in "${!TEST_SCRIPTS[@]}"; do
        local script="${TEST_SCRIPTS[$test_name]}"
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
        echo "Discovered Test Suites:"
        for prefix in $(printf '%s\n' "${!SUITE_TESTS[@]}" | sort); do
            local suite_name="${SUITE_GROUPS[$prefix]}"
            echo "  [$prefix] $suite_name:"
            for test in ${SUITE_TESTS[$prefix]}; do
                echo "    - $test: ${TEST_DESCRIPTIONS[$test]}"
            done
        done
        echo ""
    } >> "$FULL_REPORT"
}

# Run a single test script
run_test_script() {
    local test_name="$1"
    local script="${TEST_SCRIPTS[$test_name]}"
    local test_report="$REPORT_DIR/${test_name}_report_$TIMESTAMP.txt"
    
    print_header "Running Test: $test_name"
    print_info "Description: ${TEST_DESCRIPTIONS[$test_name]}"
    print_info "Script: $script"
    print_info "Report: $test_report"
    
    ((TOTAL_SUITES++))
    
    # Run the test script and capture output
    local start_time end_time duration
    start_time=$(date +%s)
    
    echo "Running test: $test_name" >> "$FULL_REPORT"
    echo "Description: ${TEST_DESCRIPTIONS[$test_name]}" >> "$FULL_REPORT"
    echo "Script: $script" >> "$FULL_REPORT"
    echo "Started: $(date)" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
    
    if "$script" > "$test_report" 2>&1; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_success "Test '$test_name' passed (${duration}s)"
        ((PASSED_SUITES++))
        SUITE_RESULTS+=("PASS: $test_name (${duration}s)")
        
        echo "Result: PASSED" >> "$FULL_REPORT"
        echo "Duration: ${duration}s" >> "$FULL_REPORT"
    else
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        log_error "Test '$test_name' failed (${duration}s)"
        FAILED_SUITES+=("$test_name")
        SUITE_RESULTS+=("FAIL: $test_name (${duration}s)")
        
        echo "Result: FAILED" >> "$FULL_REPORT"
        echo "Duration: ${duration}s" >> "$FULL_REPORT"
        
        # Show last few lines of output for quick diagnosis
        print_info "Last few lines of output:"
        tail -10 "$test_report" | sed 's/^/  /'
    fi
    
    echo "Completed: $(date)" >> "$FULL_REPORT"
    echo "" >> "$FULL_REPORT"
    
    # Append test report to full report
    echo "=== DETAILED OUTPUT ===" >> "$FULL_REPORT"
    cat "$test_report" >> "$FULL_REPORT"
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
    # First load configuration and discover tests to show current ones
    parse_yaml_config "$YAML_CONFIG" >/dev/null 2>&1
    discover_test_scripts >/dev/null 2>&1
    
    cat << EOF
BACKUP SYSTEM TEST ORCHESTRATOR

Usage: $0 [options] [tests/suites...]

Options:
  --help, -h          Show this help message
  --list-suites       List available test suites and individual tests
  --suite PREFIXES    Run all tests in specific suite(s) (comma-separated prefixes)
  --suite-name NAME   Run all tests in specific suite by shortname
  --quick             Run only quick tests (skip performance tests)
  --cleanup-only      Only cleanup test artifacts
  --no-cleanup        Don't cleanup after tests
  --report-dir DIR    Custom directory for reports (default: /tmp/backup-test-reports)

Test Suites (by prefix):
EOF

    # Show test suites dynamically
    for prefix in $(printf '%s\n' "${!SUITE_TESTS[@]}" | sort); do
        local suite_name="${SUITE_GROUPS[$prefix]}"
        echo "  [$prefix] $suite_name:"
        for test in ${SUITE_TESTS[$prefix]}; do
            echo "    - $test: ${TEST_DESCRIPTIONS[$test]}"
        done
    done

    cat << EOF

Suite Short Names:
EOF
    for shortname in $(printf '%s\n' "${!SHORTNAME_TO_PREFIXES[@]}" | sort); do
        local prefixes="${SHORTNAME_TO_PREFIXES[$shortname]}"
        echo "  $shortname (prefixes: $prefixes)"
    done

    cat << EOF

Individual Tests:
EOF
    for test in $(printf '%s\n' "${!TEST_SCRIPTS[@]}" | sort); do
        echo "  $test"
    done

    cat << EOF

Examples:
  $0                           Run all test scripts
  $0 10-test_environment       Run only environment test
  $0 20-test_connectivity 30-test_help_functionality   Run specific tests
  $0 --suite 20                Run all connectivity tests (20-* prefix)
  $0 --suite 40,50             Run all basic and advanced functionality tests
  $0 --suite-name Environment  Run all Environment tests
  $0 --suite-name Connectivity,BasicFunctionality  Run multiple suite shortnames
  $0 --quick                   Run quick tests only (skip performance)
  $0 --list-suites             Show all available tests grouped by suite
  
Report files are saved to: $REPORT_DIR
EOF
}

# Get all tests for specified suite prefixes
get_suite_tests() {
    local prefixes="$1"
    local suite_tests=()
    
    # Split comma-separated prefixes
    IFS=',' read -ra PREFIX_ARRAY <<< "$prefixes"
    
    for prefix in "${PREFIX_ARRAY[@]}"; do
        # Remove any whitespace
        prefix=$(echo "$prefix" | tr -d ' ')
        
        # Validate prefix format (should be 2 digits)
        if [[ ! "$prefix" =~ ^[0-9][0-9]$ ]]; then
            echo "Error: Invalid suite prefix '$prefix'. Must be 2 digits (e.g., 10, 20, 30)" >&2
            return 1
        fi
        
        # Check if suite exists
        if [[ -z "${SUITE_TESTS[$prefix]:-}" ]]; then
            echo "Error: No tests found for suite prefix '$prefix'" >&2
            echo "Available prefixes: $(printf '%s ' "${!SUITE_TESTS[@]}" | sort)" >&2
            return 1
        fi
        
        # Add tests from this suite
        for test in ${SUITE_TESTS[$prefix]}; do
            suite_tests+=("$test")
        done
    done
    
    # Return sorted unique tests
    printf '%s\n' "${suite_tests[@]}" | sort -u
}

# Get all tests for specified suite shortnames
get_suite_tests_by_shortname() {
    local shortname_list="$1"
    local suite_tests=()
    
    # Split comma-separated shortnames
    IFS=',' read -ra shortnames <<< "$shortname_list"
    
    for shortname in "${shortnames[@]}"; do
        # Strip whitespace
        shortname=$(echo "$shortname" | xargs)
        
        # Check if shortname exists
        if [[ -z "${SHORTNAME_TO_PREFIXES[$shortname]:-}" ]]; then
            echo "Error: Unknown suite shortname: $shortname" >&2
            echo "Available shortnames: $(printf '%s ' "${!SHORTNAME_TO_PREFIXES[@]}" | sort)" >&2
            return 1
        fi
        
        # Get prefixes for this shortname and add their tests
        local prefixes="${SHORTNAME_TO_PREFIXES[$shortname]}"
        for prefix in $prefixes; do
            if [[ -n "${SUITE_TESTS[$prefix]:-}" ]]; then
                for test in ${SUITE_TESTS[$prefix]}; do
                    suite_tests+=("$test")
                done
            fi
        done
    done
    
    # Return sorted unique tests
    printf '%s\n' "${suite_tests[@]}" | sort -u
}

# Parse command line arguments
parse_arguments() {
    local tests_to_run=()
    local no_cleanup=false
    local cleanup_only=false
    local quick_mode=false
    
    # Load configuration and discover tests first so we can validate arguments
    parse_yaml_config "$YAML_CONFIG" >/dev/null 2>&1
    discover_test_scripts >/dev/null 2>&1
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --list-suites)
                echo "Available test suites and tests:"
                echo ""
                for prefix in $(printf '%s\n' "${!SUITE_TESTS[@]}" | sort); do
                    local suite_name="${SUITE_GROUPS[$prefix]}"
                    echo "[$prefix] $suite_name:"
                    for test in ${SUITE_TESTS[$prefix]}; do
                        echo "  - $test: ${TEST_DESCRIPTIONS[$test]}"
                    done
                    echo ""
                done
                exit 0
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            --suite)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --suite requires a prefix argument (e.g., 20 or 20,30,40)"
                    exit 1
                fi
                # Get all tests for the specified suite prefixes
                local suite_test_list
                if ! suite_test_list=$(get_suite_tests "$2"); then
                    exit 1
                fi
                # Add suite tests to our list
                while IFS= read -r test; do
                    [[ -n "$test" ]] && tests_to_run+=("$test")
                done <<< "$suite_test_list"
                shift 2
                ;;
            --suite-name)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --suite-name requires a shortname argument (e.g., Environment or Connectivity,BasicFunctionality)"
                    exit 1
                fi
                # Get all tests for the specified suite shortnames
                local suite_test_list
                if ! suite_test_list=$(get_suite_tests_by_shortname "$2"); then
                    exit 1
                fi
                # Add suite tests to our list
                while IFS= read -r test; do
                    [[ -n "$test" ]] && tests_to_run+=("$test")
                done <<< "$suite_test_list"
                shift 2
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
                # Run all tests in sorted order
                readarray -t tests_to_run < <(printf '%s\n' "${!TEST_SCRIPTS[@]}" | sort)
                shift
                ;;
            [0-9][0-9]-*)
                # Check if it's a valid test name
                if [[ -n "${TEST_SCRIPTS[$1]:-}" ]]; then
                    tests_to_run+=("$1")
                else
                    echo "Error: Unknown test: $1"
                    echo "Use --list-suites to see available tests"
                    exit 1
                fi
                shift
                ;;
            *)
                echo "Error: Unknown option or test: $1"
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
    
    # Default to all tests if none specified
    if [[ ${#tests_to_run[@]} -eq 0 ]]; then
        if [[ "$quick_mode" == "true" ]]; then
            # In quick mode, run all except performance tests (60-prefix)
            for test in $(printf '%s\n' "${!TEST_SCRIPTS[@]}" | sort); do
                if [[ ! "$test" =~ ^60- ]]; then
                    tests_to_run+=("$test")
                fi
            done
        else
            # Run all tests in sorted order
            readarray -t tests_to_run < <(printf '%s\n' "${!TEST_SCRIPTS[@]}" | sort)
        fi
    fi
    
    # Remove performance tests in quick mode
    if [[ "$quick_mode" == "true" ]]; then
        local filtered_tests=()
        for test in "${tests_to_run[@]}"; do
            if [[ ! "$test" =~ ^60- ]]; then
                filtered_tests+=("$test")
            fi
        done
        tests_to_run=("${filtered_tests[@]}")
    fi
    
    # Export variables for main function
    TESTS_TO_RUN=("${tests_to_run[@]}")
    NO_CLEANUP="$no_cleanup"
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Show banner
    print_banner "BACKUP SYSTEM COMPREHENSIVE TEST SUITE"
    echo -e "Running tests: ${YELLOW}${TESTS_TO_RUN[*]}${NC}"
    echo -e "Report directory: ${BLUE}$REPORT_DIR${NC}"
    echo
    
    # Initialize
    init_test_environment
    
    # Run selected test scripts
    for test in "${TESTS_TO_RUN[@]}"; do
        if [[ -n "${TEST_SCRIPTS[$test]:-}" ]]; then
            run_test_script "$test"
        else
            log_error "Unknown test: $test"
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
