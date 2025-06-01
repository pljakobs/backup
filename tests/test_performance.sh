#!/bin/bash
# Performance and Stress Test for Backup System
# Tests system behavior under load and various edge cases

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Test configuration
BACKUP_SCRIPT="$(dirname "$(dirname "$(realpath "$0")")")/backup-new.sh"
METRICS_SCRIPT="$(dirname "$(dirname "$(realpath "$0")")")/backup-metrics"
TEST_BASE_DIR="/tmp/backup-stress-test"
PERF_LOG_FILE="$TEST_BASE_DIR/performance.log"

print_header() {
    echo -e "${CYAN}━━━ $1 ━━━${NC}"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Setup stress test environment
setup_stress_test() {
    print_header "Setting up stress test environment"
    
    mkdir -p "$TEST_BASE_DIR"/{config,source,backup,logs}
    
    # Create large test dataset
    print_info "Creating test dataset with various file sizes..."
    
    # Small files (1000 files, 1KB each)
    mkdir -p "$TEST_BASE_DIR/source/small_files"
    for i in {1..1000}; do
        dd if=/dev/urandom of="$TEST_BASE_DIR/source/small_files/file_$i.txt" bs=1024 count=1 2>/dev/null
    done
    
    # Medium files (100 files, 100KB each)
    mkdir -p "$TEST_BASE_DIR/source/medium_files"
    for i in {1..100}; do
        dd if=/dev/urandom of="$TEST_BASE_DIR/source/medium_files/file_$i.dat" bs=102400 count=1 2>/dev/null
    done
    
    # Large files (10 files, 10MB each)
    mkdir -p "$TEST_BASE_DIR/source/large_files"
    for i in {1..10}; do
        dd if=/dev/urandom of="$TEST_BASE_DIR/source/large_files/file_$i.bin" bs=1048576 count=10 2>/dev/null
    done
    
    # Deep directory structure
    mkdir -p "$TEST_BASE_DIR/source/deep_structure"
    local current_dir="$TEST_BASE_DIR/source/deep_structure"
    for i in {1..20}; do
        current_dir="$current_dir/level_$i"
        mkdir -p "$current_dir"
        echo "Content at level $i" > "$current_dir/file.txt"
    done
    
    # Special characters in filenames
    mkdir -p "$TEST_BASE_DIR/source/special_chars"
    touch "$TEST_BASE_DIR/source/special_chars/file with spaces.txt"
    touch "$TEST_BASE_DIR/source/special_chars/file-with-dashes.txt"
    touch "$TEST_BASE_DIR/source/special_chars/file_with_underscores.txt"
    touch "$TEST_BASE_DIR/source/special_chars/file.with.dots.txt"
    
    # Create stress test configuration
    cat > "$TEST_BASE_DIR/config/backup.yaml" << 'EOF'
backup_base: "/tmp/backup-stress-test/backup/"
lock_file: "/tmp/backup-stress-test.lock"
rsync_options: "-avz --stats --human-readable"

hosts:
  stresshost1:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/backup-stress-test/source/small_files"
        dest_subdir: "small"
      - path: "/tmp/backup-stress-test/source/medium_files"
        dest_subdir: "medium"
      - path: "/tmp/backup-stress-test/source/large_files"
        dest_subdir: "large"
  stresshost2:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/backup-stress-test/source/deep_structure"
        dest_subdir: "deep"
      - path: "/tmp/backup-stress-test/source/special_chars"
        dest_subdir: "special"
EOF

    cat > "$TEST_BASE_DIR/config/influxdb-config.yaml" << 'EOF'
influxdb:
  url: "http://localhost:8086"
  token: "stress-test-token"
  org: "stress-test-org"
  bucket: "stress-metrics"
EOF

    print_success "Stress test environment setup completed"
    echo "  Small files: 1000 x 1KB"
    echo "  Medium files: 100 x 100KB"
    echo "  Large files: 10 x 10MB"
    echo "  Deep structure: 20 levels"
    echo "  Special chars: various filename formats"
}

# Performance timing test
test_backup_performance() {
    print_header "Testing Backup Performance"
    
    local start_time end_time duration
    
    # Initial backup (should be slower)
    print_info "Running initial backup (full copy)..."
    start_time=$(date +%s.%N)
    
    local output
    output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Initial backup failed with exit code $exit_code"
        return 1
    fi
    
    print_success "Initial backup completed in ${duration}s"
    echo "PERF: initial_backup_time=${duration}s" >> "$PERF_LOG_FILE"
    
    # Incremental backup (should be faster)
    print_info "Running incremental backup (no changes)..."
    start_time=$(date +%s.%N)
    
    output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
    exit_code=$?
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Incremental backup failed with exit code $exit_code"
        return 1
    fi
    
    print_success "Incremental backup completed in ${duration}s"
    echo "PERF: incremental_backup_time=${duration}s" >> "$PERF_LOG_FILE"
    
    return 0
}

# Test rapid consecutive backups
test_rapid_consecutive_backups() {
    print_header "Testing Rapid Consecutive Backups"
    
    local run_ids=()
    local durations=()
    
    for i in {1..5}; do
        print_info "Running rapid backup $i/5..."
        
        local start_time end_time duration
        start_time=$(date +%s.%N)
        
        local output
        output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
        local exit_code=$?
        
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l)
        
        if [[ $exit_code -ne 0 ]]; then
            print_failure "Rapid backup $i failed with exit code $exit_code"
            return 1
        fi
        
        # Extract run ID
        local runid
        runid=$(echo "$output" | grep "Generated run ID:" | sed 's/.*Generated run ID: //')
        
        if [[ -z "$runid" ]]; then
            print_failure "Could not extract run ID from rapid backup $i"
            return 1
        fi
        
        run_ids+=("$runid")
        durations+=("$duration")
        
        print_info "  Backup $i: run_id=$runid, duration=${duration}s"
        
        # Brief pause to ensure run ID uniqueness
        sleep 0.1
    done
    
    # Verify all run IDs are unique
    local unique_ids=($(printf '%s\n' "${run_ids[@]}" | sort -u))
    
    if [[ ${#unique_ids[@]} -ne ${#run_ids[@]} ]]; then
        print_failure "Non-unique run IDs detected in rapid backups"
        return 1
    fi
    
    print_success "Rapid consecutive backups: ${#run_ids[@]} unique run IDs generated"
    echo "PERF: rapid_backups_count=${#run_ids[@]}" >> "$PERF_LOG_FILE"
    
    return 0
}

# Test metrics script under load
test_metrics_performance() {
    print_header "Testing Metrics Script Performance"
    
    # First, generate several backup runs for metrics to parse
    print_info "Generating backup runs for metrics testing..."
    
    for i in {1..10}; do
        cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup >/dev/null 2>&1
        sleep 1
    done
    
    # Test metrics script performance
    local start_time end_time duration
    
    print_info "Testing --last-run performance..."
    start_time=$(date +%s.%N)
    
    local output
    output=$(cd "$TEST_BASE_DIR/config" && "$METRICS_SCRIPT" --last-run 2>&1)
    local exit_code=$?
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Metrics --last-run failed with exit code $exit_code"
        return 1
    fi
    
    print_success "Metrics --last-run completed in ${duration}s"
    echo "PERF: metrics_last_run_time=${duration}s" >> "$PERF_LOG_FILE"
    
    # Test with multiple runs
    print_info "Testing --runs 10 performance..."
    start_time=$(date +%s.%N)
    
    output=$(cd "$TEST_BASE_DIR/config" && "$METRICS_SCRIPT" --last-run --runs 10 2>&1)
    exit_code=$?
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Metrics --runs 10 failed with exit code $exit_code"
        return 1
    fi
    
    print_success "Metrics --runs 10 completed in ${duration}s"
    echo "PERF: metrics_multiple_runs_time=${duration}s" >> "$PERF_LOG_FILE"
    
    return 0
}

# Test large file handling
test_large_file_handling() {
    print_header "Testing Large File Handling"
    
    # Create a very large file (100MB)
    print_info "Creating 100MB test file..."
    dd if=/dev/urandom of="$TEST_BASE_DIR/source/large_test_file.bin" bs=1048576 count=100 2>/dev/null
    
    # Update config to include large file
    cat >> "$TEST_BASE_DIR/config/backup.yaml" << 'EOF'
  largefile:
    hostname: "localhost"
    ssh_user: ""
    ssh_key: ""
    ignore_ping: true
    paths:
      - path: "/tmp/backup-stress-test/source/large_test_file.bin"
        dest_subdir: "largefile"
EOF

    local start_time end_time duration
    start_time=$(date +%s.%N)
    
    local output
    output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Large file backup failed with exit code $exit_code"
        return 1
    fi
    
    # Verify file was backed up correctly
    local original_size backup_size
    original_size=$(stat -c%s "$TEST_BASE_DIR/source/large_test_file.bin")
    backup_size=$(stat -c%s "$TEST_BASE_DIR/backup/largefile/large_test_file.bin" 2>/dev/null || echo "0")
    
    if [[ "$original_size" -ne "$backup_size" ]]; then
        print_failure "Large file backup size mismatch: original=$original_size, backup=$backup_size"
        return 1
    fi
    
    print_success "Large file (100MB) backup completed in ${duration}s"
    echo "PERF: large_file_backup_time=${duration}s" >> "$PERF_LOG_FILE"
    echo "PERF: large_file_size_mb=100" >> "$PERF_LOG_FILE"
    
    return 0
}

# Test concurrent backup attempts (should be prevented by lock file)
test_concurrent_backup_prevention() {
    print_header "Testing Concurrent Backup Prevention"
    
    # Start a backup in the background
    print_info "Starting background backup..."
    (cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup >/dev/null 2>&1) &
    local bg_pid=$!
    
    # Give it time to acquire lock
    sleep 2
    
    # Try to start another backup
    print_info "Attempting concurrent backup (should fail)..."
    local output
    output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    # Wait for background process
    wait $bg_pid
    local bg_exit_code=$?
    
    # The concurrent backup should fail
    if [[ $exit_code -eq 0 ]]; then
        print_failure "Concurrent backup should have failed but succeeded"
        return 1
    fi
    
    # The background backup should succeed
    if [[ $bg_exit_code -ne 0 ]]; then
        print_failure "Background backup failed with exit code $bg_exit_code"
        return 1
    fi
    
    # Check error message
    if [[ ! "$output" =~ "lock" ]] && [[ ! "$output" =~ "already running" ]]; then
        print_warning "Concurrent backup failed but without clear lock message"
    fi
    
    print_success "Concurrent backup prevention working correctly"
    return 0
}

# Test system resource usage
test_resource_usage() {
    print_header "Testing System Resource Usage"
    
    print_info "Monitoring resource usage during backup..."
    
    # Start resource monitoring
    local monitor_pid
    (
        while true; do
            # Log memory and CPU usage
            local mem_usage cpu_usage
            mem_usage=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ')
            cpu_usage=$(ps -o %cpu= -p $$ 2>/dev/null | tr -d ' ')
            
            echo "RESOURCE: timestamp=$(date +%s) memory_kb=$mem_usage cpu_percent=$cpu_usage" >> "$PERF_LOG_FILE"
            sleep 1
        done
    ) &
    monitor_pid=$!
    
    # Run backup
    local output
    output=$(cd "$TEST_BASE_DIR/config" && "$BACKUP_SCRIPT" --backup 2>&1)
    local exit_code=$?
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null
    wait $monitor_pid 2>/dev/null
    
    if [[ $exit_code -ne 0 ]]; then
        print_failure "Resource usage test backup failed"
        return 1
    fi
    
    print_success "Resource usage monitoring completed"
    return 0
}

# Cleanup stress test environment
cleanup_stress_test() {
    print_header "Cleaning up stress test environment"
    
    # Remove all test data
    rm -rf "$TEST_BASE_DIR"
    rm -f "/tmp/backup-stress-test.lock"
    
    print_success "Stress test cleanup completed"
}

# Generate performance report
generate_performance_report() {
    print_header "Performance Test Report"
    
    if [[ ! -f "$PERF_LOG_FILE" ]]; then
        print_warning "No performance log file found"
        return
    fi
    
    echo -e "${WHITE}Performance Metrics:${NC}"
    
    # Extract and display performance metrics
    local initial_time incremental_time metrics_time
    initial_time=$(grep "initial_backup_time" "$PERF_LOG_FILE" | cut -d= -f2 | sed 's/s$//')
    incremental_time=$(grep "incremental_backup_time" "$PERF_LOG_FILE" | cut -d= -f2 | sed 's/s$//')
    metrics_time=$(grep "metrics_last_run_time" "$PERF_LOG_FILE" | cut -d= -f2 | sed 's/s$//')
    
    [[ -n "$initial_time" ]] && echo "  Initial backup time: ${initial_time}s"
    [[ -n "$incremental_time" ]] && echo "  Incremental backup time: ${incremental_time}s"
    [[ -n "$metrics_time" ]] && echo "  Metrics query time: ${metrics_time}s"
    
    local rapid_count
    rapid_count=$(grep "rapid_backups_count" "$PERF_LOG_FILE" | cut -d= -f2)
    [[ -n "$rapid_count" ]] && echo "  Rapid backups completed: $rapid_count"
    
    # Calculate improvement ratio
    if [[ -n "$initial_time" && -n "$incremental_time" ]]; then
        local improvement
        improvement=$(echo "scale=2; $initial_time / $incremental_time" | bc -l)
        echo "  Incremental improvement: ${improvement}x faster"
    fi
    
    echo
    echo -e "${WHITE}Full performance log available at:${NC} $PERF_LOG_FILE"
}

# Main stress test execution
main() {
    print_header "Backup System Performance and Stress Test Suite"
    echo "Testing system behavior under load and edge cases"
    echo
    
    local tests_passed=0
    local tests_total=6
    
    # Initialize performance log
    echo "# Backup System Performance Test Results" > "$PERF_LOG_FILE"
    echo "# Started: $(date)" >> "$PERF_LOG_FILE"
    
    # Setup
    setup_stress_test
    
    # Run stress tests
    if test_backup_performance; then ((tests_passed++)); fi
    if test_rapid_consecutive_backups; then ((tests_passed++)); fi
    if test_metrics_performance; then ((tests_passed++)); fi
    if test_large_file_handling; then ((tests_passed++)); fi
    if test_concurrent_backup_prevention; then ((tests_passed++)); fi
    if test_resource_usage; then ((tests_passed++)); fi
    
    # Generate report
    generate_performance_report
    
    # Cleanup
    cleanup_stress_test
    
    # Results
    echo
    print_header "Stress Test Results"
    echo -e "Passed: ${GREEN}$tests_passed${NC}/$tests_total"
    
    if [[ $tests_passed -eq $tests_total ]]; then
        echo -e "${GREEN}All stress tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some stress tests failed!${NC}"
        exit 1
    fi
}

# Handle arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo
        echo "Performance and Stress Test Suite"
        echo "Tests system behavior under load and various edge cases"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --setup-only  Only setup test environment"
        echo "  --cleanup     Only cleanup test environment"
        exit 0
        ;;
    "--setup-only")
        setup_stress_test
        exit 0
        ;;
    "--cleanup")
        cleanup_stress_test
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
