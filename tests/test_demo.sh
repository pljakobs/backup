#!/bin/bash

# Demo script to show the refactored test library in action

set -euo pipefail

# Source common test library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Demo test functions
demo_test_pass() {
    log_info "Running a test that will pass..."
    run_test
    
    # Simulate some work
    sleep 0.1
    
    log_success "This test passed successfully!"
    return 0
}

demo_test_fail() {
    log_info "Running a test that will fail..."
    run_test
    
    # Simulate some work
    sleep 0.1
    
    log_error "This test failed as expected!"
    return 1
}

demo_test_skip() {
    log_info "Running a test that will be skipped..."
    run_test
    
    # Simulate some work
    sleep 0.1
    
    log_skip "This test was skipped for demo purposes!"
    return 0
}

# Main function
main() {
    print_banner "TEST LIBRARY DEMONSTRATION"
    
    log_info "Demonstrating the refactored test library functionality"
    echo ""
    
    # Set up test count
    increment_tests_total  # demo_test_pass
    increment_tests_total  # demo_test_fail  
    increment_tests_total  # demo_test_skip
    
    # Run demo tests
    demo_test_pass || true
    echo ""
    
    demo_test_fail || true
    echo ""
    
    demo_test_skip || true
    echo ""
    
    # Print summary
    print_test_summary "Demo Test"
}

# Run the tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
