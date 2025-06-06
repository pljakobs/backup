# Test Suite Organization

## Overview
The backup system test suite is now organized using numeric prefixes that ensure logical execution order and dynamic test discovery.

## Naming Convention

### Numeric Prefixes
Tests are organized into logical groups using two-digit numeric prefixes:

- **10-**: Environment tests (basic infrastructure validation)
- **20-**: Connectivity tests (network and SSH validation)  
- **30-**: User Interface tests (help functionality, basic interface)
- **40-**: Basic Functionality tests (simple features)
- **50-**: Advanced Functionality tests (complex features)
- **60-**: Performance tests (stress testing, performance validation)
- **70-**: Metrics tests (future expansion for metrics-specific tests)

### Test Description Format
Each test script must include a standardized description comment:
```bash
# TEST_DESCRIPTION: Brief description of what this test validates
```

## Current Test Structure

```
10-test_environment.sh          - Environment and prerequisite validation
20-test_connectivity.sh         - Network connectivity and SSH validation
30-test_help_functionality.sh   - Help functionality and basic interface validation
40-test_runid_simple.sh         - Simple run ID generation and format validation
50-test_runid.sh                - Advanced run ID tracking and backup functionality
60-test_performance.sh          - Performance and stress testing
```

## Dynamic Test Discovery

The test orchestrator (`run-tests.sh`) automatically discovers test scripts by:

1. Scanning for executable `.sh` files with numeric prefixes (`[0-9][0-9]-*.sh`)
2. Extracting test descriptions from `TEST_DESCRIPTION` comments
3. Grouping tests by numeric prefix into logical suites
4. Providing execution order based on numeric sorting

## Usage

### Running Tests
```bash
# Run all tests
./run-tests.sh

# Run specific test
./run-tests.sh 10-test_environment

# Run multiple tests
./run-tests.sh 10-test_environment 20-test_connectivity

# Run quick tests (skip performance)
./run-tests.sh --quick

# List all available tests
./run-tests.sh --list-suites
```

### Adding New Tests

1. Create test script with appropriate numeric prefix
2. Make it executable: `chmod +x NN-test_name.sh`
3. Add TEST_DESCRIPTION comment at the top
4. The test will be automatically discovered by the orchestrator

Example:
```bash
#!/bin/bash

# TEST_DESCRIPTION: My new test functionality
# Additional comments about the test...

set -euo pipefail
# ... test implementation
```

## Benefits

- **Logical Execution Order**: Tests run from basic to complex
- **Easy Maintenance**: No hardcoded test lists to maintain
- **Clear Organization**: Numeric prefixes show test complexity/priority
- **Flexible Execution**: Can run individual tests or groups
- **Self-Documenting**: Test descriptions show up in help and reports
- **Future Expansion**: Easy to add new test categories with new prefixes

## Quick Mode

The `--quick` option automatically excludes performance tests (60-prefix) for faster development cycles.
