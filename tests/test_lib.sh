#!/bin/bash
# Common Test Library for Backup System Tests
# Provides shared functions, colors, counters, and utilities

# Ensure this library is only sourced once
if [[ "${TEST_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
TEST_LIB_LOADED=true

# Color definitions for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Global test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TESTS_TOTAL=0

# Test result tracking
TEST_RESULTS=()

# Default container and script paths (can be overridden by test scripts)
BACKUP_CONTAINER="${BACKUP_CONTAINER:-backup-test}"
BACKUP_SCRIPT="${BACKUP_SCRIPT:-/opt/backup/backup-new.sh}"
METRICS_SCRIPT="${METRICS_SCRIPT:-/opt/backup/backup-metrics}"

# Common logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Print functions with different styling
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_test_header() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

print_banner() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                     $1                       ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_test_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_test_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
    TEST_RESULTS+=("FAIL: $1")
}

print_test_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_test_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Timestamp function
print_timestamp() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Test counter functions
run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
}

increment_tests_total() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# Helper function to run a single test with proper counting
run_single_test() {
    local test_name="$1"
    local test_function="$2"
    
    run_test
    log_info "Running: $test_name"
    
    if $test_function; then
        return 0
    else
        return 1
    fi
}

# Test result tracking function
print_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local log_file="${4:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$status" == "PASS" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name - $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ -n "$log_file" ]]; then
            print_timestamp "PASS: $test_name - $message" >> "$log_file"
        fi
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS+=("FAIL: $test_name - $message")
        if [[ -n "$log_file" ]]; then
            print_timestamp "FAIL: $test_name - $message" >> "$log_file"
        fi
    fi
}

# Container management functions
run_in_container() {
    local container="$1"
    local command="$2"
    
    podman exec "$container" bash -c "$command"
}

check_container_running() {
    local container="$1"
    
    if podman ps --format "{{.Names}}" | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Test implementation functions have been moved to specific test files

# Summary and reporting functions
print_test_summary() {
    local script_name="${1:-Test Script}"
    
    echo
    echo -e "${BLUE}=== TEST SUMMARY for $script_name ===${NC}"
    echo -e "Tests run:    ${YELLOW}$TESTS_RUN${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
    fi
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some tests failed!${NC}"
        if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then
            echo -e "\n${RED}Failed tests:${NC}"
            for result in "${TEST_RESULTS[@]}"; do
                echo -e "  ${RED}•${NC} $result"
            done
        fi
        return 1
    fi
}

print_summary() {
    print_test_summary "$@"
}

# Environment setup functions
setup_test_log() {
    local log_file="$1"
    local script_name="${2:-Test Script}"
    
    mkdir -p "$(dirname "$log_file")"
    cat > "$log_file" << EOF
$script_name Test Log
===================
Started: $(date)

EOF
}

# File/directory helper functions
create_temp_test_dir() {
    local base_name="${1:-test}"
    local temp_dir="/tmp/${base_name}-$$-$(date +%s)"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

cleanup_temp_dir() {
    local temp_dir="$1"
    if [[ -n "$temp_dir" && "$temp_dir" =~ ^/tmp/ ]]; then
        rm -rf "$temp_dir"
    fi
}

# Script path helpers
get_backup_script_path() {
    echo "$(dirname "$(dirname "$(realpath "$0")")")/backup-new.sh"
}

get_metrics_script_path() {
    echo "$(dirname "$(dirname "$(realpath "$0")")")/backup-metrics"
}

# Reset counters (useful for multiple test runs)
reset_test_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0
    TESTS_TOTAL=0
    TEST_RESULTS=()
}

# Export functions that might be used in subshells
export -f log_info log_success log_error log_warning log_skip
export -f print_header print_test_header print_banner
export -f print_test_info print_test_success print_test_failure print_test_warning print_test_skip
export -f print_success print_failure print_info print_timestamp
export -f run_test increment_tests_total print_test_result
export -f run_in_container check_container_running
export -f print_test_summary print_summary setup_test_log
export -f create_temp_test_dir cleanup_temp_dir
export -f get_backup_script_path get_metrics_script_path reset_test_counters
