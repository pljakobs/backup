#!/bin/bash

# TEST_DESCRIPTION: teardown test environment and cleanup all resources
# TEST_TIMEOUT: 180

# Source test library for consistent logging
source "$(dirname "$0")/test_lib.sh"

print_header "Starting Environment Teardown"
log_info "Cleaning up all test containers, networks, volumes, and artifacts..."

# Use the container cleanup script from the tests/containers subfolder
if [[ -f "./containers/test-environment.sh" ]]; then
        log_info "Running comprehensive container cleanup..."
        ./containers/test-environment.sh clean --volumes
        
        # Also clean up network (the script doesn't handle this)
        log_info "Removing backup test network..."
        podman network rm backup-test-network 2>/dev/null || true
        
        # Clean up any remaining backup-related volumes that might have been missed
        log_info "Cleaning up any remaining backup volumes..."
        podman volume ls --format "{{.Name}}" | grep -E "^backup" | while read -r volume; do
            if [[ -n "$volume" ]]; then
                log_info "  Removing volume: $volume"
                podman volume rm "$volume" 2>/dev/null || true
            fi
        done
        
        if [[ $? -eq 0 ]]; then
            log_success "Container cleanup completed successfully"
        else
            log_warning "Container cleanup completed with warnings"
        fi
else
    log_warning "Container cleanup script not found, performing manual cleanup..."
    
    # Manual cleanup fallback
    log_info "Stopping and removing backup test containers..."
    podman ps -a --filter "name=backup-" --format "{{.Names}}" | while read -r container; do
        if [[ -n "$container" ]]; then
            log_info "  Stopping container: $container"
            podman stop "$container" 2>/dev/null || true
            log_info "  Removing container: $container"
            podman rm "$container" 2>/dev/null || true
        fi
    done
    
    log_info "Removing backup test network..."
    podman network rm backup-test-network 2>/dev/null || true
    
    log_info "Removing backup test volumes..."
    podman volume rm backup-shared 2>/dev/null || true
    podman volume rm backup-data 2>/dev/null || true
    podman volume rm influxdb-data 2>/dev/null || true
    podman volume rm grafana-data 2>/dev/null || true
fi

# Clean up any generated configuration files
log_info "Cleaning up generated configuration files..."
if [[ -f "./containers/backup-configured.yaml" ]]; then
    rm -f "./containers/backup-configured.yaml"
    print_success "Removed generated backup configuration"
fi

# Clean up any temporary SSH keys or other test artifacts
log_info "Cleaning up temporary test artifacts..."
find /tmp -name "*backup-test*" -type f -mtime -1 2>/dev/null | while read -r file; do
    if [[ -n "$file" ]]; then
        rm -f "$file" 2>/dev/null || true
        log_info "  Removed: $file"
    fi
done

# Verify cleanup was successful
print_header "Verifying Cleanup"
remaining_containers=$(podman ps -a --filter "name=backup-" --format "{{.Names}}" | wc -l)
if [[ "$remaining_containers" -eq 0 ]]; then
    print_success "All backup test containers removed"
else
    log_warning "$remaining_containers backup test containers still exist"
    podman ps -a --filter "name=backup-" --format "table {{.Names}}\t{{.Status}}"
fi

# Check if network still exists
if podman network exists backup-test-network 2>/dev/null; then
    log_warning "backup-test-network still exists"
else
    print_success "Backup test network removed"
fi

# Check for any remaining volumes
remaining_volumes=$(podman volume ls --filter "name=backup-" --format "{{.Name}}" | wc -l)
if [[ "$remaining_volumes" -eq 0 ]]; then
    print_success "All backup test volumes removed"
else
    log_warning "$remaining_volumes backup test volumes still exist"
    podman volume ls --filter "name=backup-" --format "table {{.Name}}\t{{.Driver}}"
fi

print_header "Environment Teardown Complete"
log_success "All test resources have been cleaned up"

# Always exit successfully for teardown - we don't want cleanup failures to fail the overall test run
exit 0
