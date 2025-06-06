# Backup System Test Organization - Complete Guide

This document describes the completely reorganized test system for the backup system test suite, featuring YAML-based configuration and dynamic test discovery.

## Overview

The test system has been completely rewritten to provide:
- **Logical test ordering** through numeric prefixes
- **Dynamic test discovery** to automatically find and organize tests
- **YAML-based suite configuration** for flexible suite management
- **Suite shortname support** for easy test execution
- **Comprehensive reporting** with detailed output and timing
- **Flexible execution modes** for development and CI/CD

## Test Organization Structure

### Numeric Prefix System

Tests are organized using a two-digit prefix system that determines both execution order and logical grouping:

- **[10]** Environment - Environment and prerequisite validation tests
- **[20]** Connectivity - Network connectivity and SSH validation tests  
- **[30]** UserInterface - User interface, help functionality, and basic interface validation tests
- **[40]** BasicFunctionality - Basic functionality and simple feature validation tests
- **[50]** AdvancedFunctionality - Advanced functionality and complex feature validation tests
- **[60]** Performance - Performance testing, stress testing, and resource validation
- **[70]** Metrics - Metrics collection, monitoring, and reporting validation tests

### Current Test Files

```
10-test_environment.sh          - Environment and prerequisite validation
20-test_connectivity.sh         - Network connectivity and SSH validation
30-test_help_functionality.sh   - Help functionality and basic interface validation
40-test_runid_simple.sh         - Simple run ID generation and format validation
50-test_runid.sh                - Advanced run ID tracking and backup functionality  
60-test_performance.sh          - Performance and stress testing
```

## YAML-Based Suite Configuration

### Configuration File: `test-suites.yaml`

The test suites are now defined in a YAML configuration file that provides:
- Flexible prefix-to-shortname mapping
- Descriptive suite documentation
- Easy reconfiguration without code changes
- Support for multiple test categories

Example configuration structure:
```yaml
suites:
  - suite:
      prefix: "1*"
      shortname: "Environment" 
      description: "Environment and prerequisite validation tests"
  - suite:
      prefix: "2*"
      shortname: "Connectivity"
      description: "Network connectivity and SSH validation tests"
```

### Suite Short Names

The following shortnames are available for easy test execution:

| Short Name | Prefix | Description |
|------------|--------|-------------|
| **Environment** | 10 | Environment validation and prerequisites |
| **Connectivity** | 20 | Network connectivity and SSH validation |
| **UserInterface** | 30 | User interface and help functionality |
| **BasicFunctionality** | 40 | Basic functionality and simple features |
| **AdvancedFunctionality** | 50 | Advanced functionality and complex features |
| **Performance** | 60 | Performance testing and stress validation |
| **Metrics** | 70 | Metrics collection and monitoring |

## Test Runner: `run-tests.sh`

### Key Features

1. **Dynamic Test Discovery** - Automatically discovers test scripts with numeric prefixes
2. **YAML Configuration Loading** - Uses `yq` to parse suite configuration with fallback support
3. **Multiple Execution Modes** - Individual tests, prefix suites, or shortname suites
4. **Comprehensive Reporting** - Detailed reports with timing, environment info, and results
5. **Flexible Options** - Quick mode, cleanup control, custom report directories
6. **Error Handling** - Robust error handling with helpful error messages

### Usage Examples

#### Running Individual Tests
```bash
# Single test
./run-tests.sh 10-test_environment

# Multiple specific tests
./run-tests.sh 20-test_connectivity 30-test_help_functionality
```

#### Running Suites by Prefix
```bash
# Single suite by prefix
./run-tests.sh --suite 20                    

# Multiple suites by prefix
./run-tests.sh --suite 40,50                 
```

#### Running Suites by Short Name (NEW!)
```bash
# Single suite by shortname
./run-tests.sh --suite-name Environment      

# Multiple suites by shortname
./run-tests.sh --suite-name Connectivity,BasicFunctionality  

# All functionality tests
./run-tests.sh --suite-name BasicFunctionality,AdvancedFunctionality
```

#### Special Execution Modes
```bash
# Run all tests (default)
./run-tests.sh                               

# Run all tests explicitly
./run-tests.sh all                          

# Quick mode (skip performance tests)
./run-tests.sh --quick                       

# Show available tests and suites
./run-tests.sh --list-suites                 
```

### Complete Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--help, -h` | Show help message with all available tests and suites | `./run-tests.sh --help` |
| `--list-suites` | List all available test suites and individual tests | `./run-tests.sh --list-suites` |
| `--suite PREFIXES` | Run tests by numeric prefix (comma-separated) | `./run-tests.sh --suite 20,30` |
| `--suite-name NAME` | Run tests by suite shortname (comma-separated) | `./run-tests.sh --suite-name Environment` |
| `--quick` | Run only quick tests (skip performance tests) | `./run-tests.sh --quick` |
| `--cleanup-only` | Only cleanup test artifacts | `./run-tests.sh --cleanup-only` |
| `--no-cleanup` | Don't cleanup after tests | `./run-tests.sh --no-cleanup` |
| `--report-dir DIR` | Custom directory for reports | `./run-tests.sh --report-dir /custom/path` |

## Test Script Requirements

### File Naming Convention
Test scripts must follow the pattern: `[0-9][0-9]-*.sh`

✅ **Valid Examples:**
- `10-test_environment.sh`
- `25-test_new_feature.sh`
- `33-test_ui_validation.sh`

❌ **Invalid Examples:**
- `test-something.sh` (missing numeric prefix)
- `1-test.sh` (single digit prefix)
- `test_environment.sh` (no numeric prefix)

### Required Headers
Each test script should include a description comment for dynamic discovery:
```bash
#!/bin/bash
# TEST_DESCRIPTION: Brief description of what this test does

set -euo pipefail
# ... test implementation
```

### Executable Permissions
All test scripts must be executable:
```bash
chmod +x [0-9][0-9]-*.sh
```

### Test Script Best Practices
```bash
#!/bin/bash
# TEST_DESCRIPTION: Environment and prerequisite validation

set -euo pipefail

# Source test library for common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test implementation
print_header "Environment Validation Test"
# ... test logic ...
log_success "Environment validation completed"
```

## Adding New Tests

### 1. Choose Appropriate Prefix
Select a prefix based on the test category and logical execution order:

- **10-19**: Environment setup and validation
- **20-29**: Connectivity and network tests  
- **30-39**: User interface and help tests
- **40-49**: Basic functionality tests
- **50-59**: Advanced functionality tests
- **60-69**: Performance and stress tests
- **70-79**: Metrics and monitoring tests
- **80-89**: Integration tests (future)
- **90-99**: End-to-end tests (future)

### 2. Create Test Script
```bash
# For a new basic functionality test
touch 45-test_new_feature.sh
chmod +x 45-test_new_feature.sh
```

### 3. Add Required Headers
```bash
#!/bin/bash
# TEST_DESCRIPTION: New feature validation and testing

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_lib.sh"

# Test implementation here
```

### 4. Verify Integration
The test will be automatically discovered on the next run:
```bash
./run-tests.sh --list-suites
```

## Extending Suite Configuration

### Adding New Suite Categories
To add new suite categories, edit `test-suites.yaml`:

```yaml
suites:
  # ...existing suites...
  - suite:
      prefix: "8*"
      shortname: "Security"
      description: "Security and authentication validation tests"
  - suite:
      prefix: "9*"
      shortname: "Integration"
      description: "End-to-end integration tests"
```

### Modifying Existing Suites
Update the shortname or description in `test-suites.yaml`. Changes take effect immediately without requiring code changes.

### YAML Configuration Validation
The system includes robust YAML parsing with:
- Fallback to hardcoded configuration if YAML file is missing
- Graceful handling if `yq` is not available
- Validation of prefix patterns and suite definitions

## Reports and Output

### Report Structure
The test system generates comprehensive reports in `/tmp/backup-test-reports/`:

```
/tmp/backup-test-reports/
├── full_test_report_20250606_091621.txt     # Complete test run report
├── 10-test_environment_report_20250606_091621.txt
├── 20-test_connectivity_report_20250606_091621.txt
└── ...
```

### Report Content
Each report includes:

#### Individual Test Reports
- Test execution details and timing
- Complete test output (stdout and stderr)
- Pass/fail status with exit codes
- Environment information
- Error details for failed tests

#### Full Test Report
- Executive summary with statistics
- Environment information
- Detailed results for each test
- Timing information
- Failed test summaries
- Complete aggregated output

### Report Customization
```bash
# Custom report directory
./run-tests.sh --report-dir /custom/reports

# Reports include timestamps for version control
full_test_report_20250606_091621.txt
```

## System Dependencies

### Required Tools
- **bash** - Shell for test execution
- **yq** - YAML processor for configuration parsing (`dnf install yq`)
- **Standard Unix tools**: `grep`, `sed`, `awk`, `sort`, `find`

### Optional Tools (Test-Specific)
- **rsync** - For backup functionality tests
- **journalctl** - For metrics and system tests
- **bc** - For performance calculations
- **ssh** - For connectivity tests

### Installation
```bash
# On Fedora/RHEL systems
sudo dnf install yq rsync systemd bc openssh-clients

# Verify installation
yq --version
rsync --version
```

## Migration and Compatibility

### From Old System
The system maintains complete backward compatibility:
- ✅ Old numeric prefix execution still works
- ✅ Fallback configuration if YAML file is missing  
- ✅ All existing test scripts work without modification
- ✅ Legacy command-line arguments are supported

### Migration Benefits
- **Zero downtime migration** - old and new systems work simultaneously
- **Gradual adoption** - can migrate tests one by one
- **Enhanced functionality** - new features don't break existing workflows

## Development Workflow

### Quick Development Cycle
```bash
# Fast feedback during development
./run-tests.sh --suite-name BasicFunctionality --quick --no-cleanup

# Test specific functionality
./run-tests.sh 40-test_runid_simple

# Full validation before commit
./run-tests.sh
```

### CI/CD Integration
```bash
# Quick CI pipeline
./run-tests.sh --quick --report-dir /ci/reports

# Full validation pipeline  
./run-tests.sh --report-dir /ci/reports

# Specific test suites
./run-tests.sh --suite-name Environment,Connectivity
```

## Troubleshooting

### Common Issues

#### YAML Configuration Issues
```bash
# Check YAML syntax
yq eval '.' test-suites.yaml

# Verify yq installation
which yq
yq --version
```

#### Test Discovery Issues
```bash
# List discovered tests
./run-tests.sh --list-suites

# Check file permissions
ls -la [0-9][0-9]-*.sh

# Verify test descriptions
grep "TEST_DESCRIPTION" [0-9][0-9]-*.sh
```

#### Report Generation Issues
```bash
# Check report directory permissions
ls -la /tmp/backup-test-reports/

# Use custom report directory
./run-tests.sh --report-dir /home/user/test-reports
```

### Debug Mode
Add debug output to test scripts:
```bash
# At the top of test scripts
set -euo pipefail
set -x  # Enable debug output
```

## Best Practices

### Test Organization
- ✅ Use logical numeric prefixes that group related functionality
- ✅ Keep test descriptions concise but descriptive
- ✅ Follow established prefix ranges for consistency
- ✅ Group related tests in the same prefix range

### Test Development
- ✅ Make tests idempotent (can be run multiple times safely)
- ✅ Include cleanup in test scripts where needed
- ✅ Use the common test library functions (`test_lib.sh`)
- ✅ Provide meaningful output and error messages
- ✅ Test both success and failure scenarios

### Suite Management
- ✅ Update YAML configuration when adding new test categories
- ✅ Use descriptive shortnames that are easy to remember
- ✅ Document any special requirements or dependencies
- ✅ Keep suite descriptions current and accurate

### Performance Considerations
- ✅ Use `--quick` mode for rapid development feedback
- ✅ Place long-running tests in the Performance category (60-prefix)
- ✅ Consider test execution time when choosing prefixes
- ✅ Use `--no-cleanup` during debugging to inspect test artifacts

## Future Enhancements

### Planned Features
- **Parallel test execution** for performance improvement
- **Test tagging system** for more flexible test selection
- **JSON report output** for CI/CD integration
- **Test dependency management** for complex test scenarios
- **Interactive test selection** for development workflows

### Extension Points
- **Custom test categories** via YAML configuration
- **Plugin system** for specialized test types
- **Remote test execution** for distributed testing
- **Test result persistence** and historical analysis
