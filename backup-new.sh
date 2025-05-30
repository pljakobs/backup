#!/bin/bash
#uses job pool from 
# https://github.com/vincetse/shellutils/blob/master/job_pool.sh

. job_pool.sh
#. /etc/backup/options

# Function to find configuration file in search paths
find_config_file() {
    local filename="$1"
    local search_paths=(
        "./${filename}"
        "/etc/backup/${filename}"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Return the /etc/backup path as default if none found
    echo "/etc/backup/${filename}"
}

# Configuration file paths with search order
CONFIG_FILE=$(find_config_file "backup.yaml")
SCRIPTS_DIR="/etc/backup/scripts"

# Global dry-run flag
DRY_RUN=false

# Default rsync options
rsyncOptions="-avz --stats --human-readable --progress --delete"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Formatting functions
print_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_command() {
    echo -e "${WHITE}→${NC} $1"
}

print_dry_run() {
    echo -e "${PURPLE}[DRY-RUN]${NC} $1"
}

# Execute command or show dry-run
execute_command() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        print_dry_run "$cmd"
    else
        print_command "$cmd"
        eval "$cmd"
    fi
}

# Function to interpret rsync exit codes
interpret_rsync_exit_code() {
    local exit_code="$1"
    local operation="$2"
    
    case $exit_code in
        0)
            echo "success"
            ;;
        1)
            echo "warning" # Syntax or usage error
            ;;
        2)
            echo "warning" # Protocol incompatibility
            ;;
        3)
            echo "warning" # Errors selecting input/output files, dirs
            ;;
        4)
            echo "failed"  # Requested action not supported
            ;;
        5)
            echo "failed"  # Error starting client-server protocol
            ;;
        6)
            echo "failed"  # Daemon unable to append to log-file
            ;;
        10)
            echo "failed"  # Error in socket I/O
            ;;
        11)
            echo "failed"  # Error in file I/O
            ;;
        12)
            echo "failed"  # Error in rsync protocol data stream
            ;;
        13)
            echo "failed"  # Errors with program diagnostics
            ;;
        14)
            echo "failed"  # Error in IPC code
            ;;
        20)
            echo "failed"  # Received SIGUSR1 or SIGINT
            ;;
        21)
            echo "failed"  # Some error returned by waitpid()
            ;;
        22)
            echo "failed"  # Error allocating core memory buffers
            ;;
        23)
            echo "warning" # Partial transfer due to error
            ;;
        24)
            echo "warning" # Partial transfer due to vanished source files
            ;;
        25)
            echo "failed"  # The --max-delete limit stopped deletions
            ;;
        30)
            echo "failed"  # Timeout in data send/receive
            ;;
        35)
            echo "failed"  # Timeout waiting for daemon connection
            ;;
        *)
            echo "failed"  # Unknown exit code
            ;;
    esac
}

function ctrl_c(){
    print_warning "Exiting on Ctrl-C..."
    backup_exit
}

function backup_exit(){
    job_pool_shutdown
    local cleanup_lock_file=$(get_config_value "lock_file" "/tmp/backup.fil")
    rm "$cleanup_lock_file" 2>/dev/null
    print_info "Backup script exited cleanly"
    exit
}

function check_lock_file(){
    local lock_file="$1"
    
    if [[ ! -f "$lock_file" ]]; then
        return 0  # No lock file, safe to proceed
    fi
    
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    
    if [[ -z "$lock_pid" || ! "$lock_pid" =~ ^[0-9]+$ ]]; then
        print_warning "Lock file exists but contains invalid PID, removing stale lock"
        rm "$lock_file" 2>/dev/null
        return 0
    fi
    
    if kill -0 "$lock_pid" 2>/dev/null; then
        print_warning "Backup already running (PID: $lock_pid), skipping for now"
        return 1
    else
        print_warning "Lock file exists but process $lock_pid is not running, removing stale lock"
        rm "$lock_file" 2>/dev/null
        return 0
    fi
}

function check_dependencies() {
    local missing_deps=()
    
    print_header "Checking Dependencies"
    
    # Check for yq
    if ! command -v yq &> /dev/null; then
        missing_deps+=("yq")
    fi
    
    # Check for btrfs-snp
    if ! command -v btrfs-snp &> /dev/null && [[ ! -f "/usr/local/sbin/btrfs-snp" ]]; then
        missing_deps+=("btrfs-snp")
    fi
    
    # Check for job_pool.sh
    if [[ ! -f "job_pool.sh" ]] && [[ ! -f "/usr/local/bin/job_pool.sh" ]]; then
        missing_deps+=("job_pool.sh")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        read -p "Would you like to install missing dependencies? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            print_error "Cannot proceed without required dependencies"
            exit 1
        fi
    else
        print_success "All dependencies are available"
    fi
}

function install_dependencies() {
    local deps=("$@")
    
    print_header "Installing missing dependencies"
    
    for dep in "${deps[@]}"; do
        case "$dep" in
            "yq")
                print_info "Installing yq..."
                if command -v apt &> /dev/null; then
                    print_command "sudo apt update && sudo apt install -y yq"
                    sudo apt update && sudo apt install -y yq
                elif command -v dnf &> /dev/null; then
                    print_command "sudo dnf install -y yq"
                    sudo dnf install -y yq
                else
                    print_error "Please install yq manually"
                    exit 1
                fi
                print_success "yq installed successfully"
                ;;
            "job_pool.sh")
                print_info "Downloading job_pool.sh..."
                print_command "curl -o job_pool.sh https://raw.githubusercontent.com/vincetse/shellutils/master/job_pool.sh"
                curl -o job_pool.sh https://raw.githubusercontent.com/vincetse/shellutils/master/job_pool.sh
                chmod +x job_pool.sh
                print_success "job_pool.sh downloaded and made executable"
                ;;
            "btrfs-snp")
                print_info "Installing btrfs-snp..."
                print_command "curl -o /usr/local/sbin/btrfs-snp https://raw.githubusercontent.com/nachoparker/btrfs-snp/refs/heads/master/btrfs-snp"
                sudo curl -o /usr/local/sbin/btrfs-snp https://raw.githubusercontent.com/nachoparker/btrfs-snp/refs/heads/master/btrfs-snp
                sudo chmod +x /usr/local/sbin/btrfs-snp
                print_success "btrfs-snp installed successfully"
                ;;
        esac
    done
}

function parse_yaml() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration file $config_file not found"
        exit 1
    fi
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required to parse YAML. Install with: sudo apt install yq"
        exit 1
    fi
    
    # Get list of hosts
    mapfile -t BACKUP_HOSTS < <(yq eval '.hosts | keys | .[]' "$config_file")
    print_success "Loaded configuration for ${#BACKUP_HOSTS[@]} hosts: ${BACKUP_HOSTS[*]}"
}

function get_host_config() {
    local hostname="$1"
    local key="$2"
    local default="$3"
    
    local value
    value=$(yq eval ".hosts.$hostname.$key // \"$default\"" "$CONFIG_FILE")
    echo "$value"
}

function get_path_config() {
    local hostname="$1"
    local path_index="$2"
    local key="$3"
    local default="$4"
    
    local value
    value=$(yq eval ".hosts.$hostname.paths[$path_index].$key // \"$default\"" "$CONFIG_FILE")
    echo "$value"
}

function get_host_paths_count() {
    local hostname="$1"
    yq eval ".hosts.$hostname.paths | length" "$CONFIG_FILE"
}

function get_config_value() {
    local key="$1"
    local default="$2"
    
    local value
    value=$(yq eval ".config.$key // \"$default\"" "$CONFIG_FILE")
    echo "$value"
}

function run_script() {
    local script_name="$1"
    local ssh_user="$2"
    local ssh_key="$3"
    local script_type="$4"  # "remote" or "local"
    
    if [[ -z "$script_name" || "$script_name" == "null" ]]; then
        return 0
    fi
    
    local script_path="$SCRIPTS_DIR/$script_name.sh"
    
    if [[ ! -f "$script_path" ]]; then
        print_warning "Script $script_path not found"
        return 1
    fi
    
    if [[ "$script_type" == "local" ]]; then
        print_info "Running local script: $script_name"
        execute_command "bash \"$script_path\""
    else
        print_info "Running remote script: $script_name on $ssh_user"
        if [[ -n "$ssh_key" && "$ssh_key" != "null" && "$ssh_key" != '""' ]]; then
            execute_command "ssh -i \"$ssh_key\" \"$ssh_user\" \"bash -s\" < \"$script_path\""
        else
            execute_command "ssh \"$ssh_user\" \"bash -s\" < \"$script_path\""
        fi
    fi
}

function backup_host() {
    local hostname="$1"
    
    print_header "Starting backup for $hostname"
    
    # Initialize host-level backup status
    BACKUP_STATUS_HOST="success"
    
    # Get host-level configuration
    local ssh_key=$(get_host_config "$hostname" "ssh_key" "~/.ssh/id_ed25519")
    local ssh_user_raw=$(get_host_config "$hostname" "ssh_user" "")
    local target_hostname=$(get_host_config "$hostname" "hostname" "$hostname")
    local exclude_file=$(get_host_config "$hostname" "exclude_file" "")
    local default_rsync_path=$(get_host_config "$hostname" "rsync_path" "")
    local preserve_ownership=$(get_host_config "$hostname" "preserve_ownership" "false")
    
    # Handle both formats: combined "user@host" or separate fields  
    local ssh_user
    if [[ "$ssh_user_raw" == *"@"* ]]; then
        # Already has user@host format
        ssh_user="$ssh_user_raw"
    elif [[ -n "$ssh_user_raw" && "$ssh_user_raw" != "null" && "$ssh_user_raw" != '""' ]]; then
        # Separate user and hostname fields
        ssh_user="$ssh_user_raw@$target_hostname"
    else
        # Local backup (empty ssh_user)
        ssh_user=""
        print_info "Local backup for $hostname (no SSH)"
    fi
    
    # Create backup directory
    local backup_base=$(get_config_value "backup_base" "/share/backup/")
    local backup_dir="$backup_base$hostname"
    if [[ ! -d "$backup_dir" ]]; then
        print_info "Creating directory $backup_dir"
        execute_command "mkdir -p \"$backup_dir\""
    else
        print_info "Directory $backup_dir already exists"
    fi
    
    # Get number of paths
    local paths_count=$(get_host_paths_count "$hostname")
    
    # Backup each configured path
    for ((i=0; i<paths_count; i++)); do
        local path=$(yq eval ".hosts.$hostname.paths[$i].path" "$CONFIG_FILE")
        [[ -z "$path" || "$path" == "null" ]] && continue
        
        print_info "Processing path: $path"
        
        # Initialize volume-level backup status
        BACKUP_STATUS_VOLUME="success"
        
        # Get path-specific configuration
        local dest_subdir=$(get_path_config "$hostname" "$i" "dest_subdir" "")
        local path_rsync_path=$(get_path_config "$hostname" "$i" "rsync_path" "$default_rsync_path")
        local path_exclude=$(get_path_config "$hostname" "$i" "exclude_file" "$exclude_file")
        local path_options=$(get_path_config "$hostname" "$i" "host_options" "")
        local pre_script=$(get_path_config "$hostname" "$i" "pre_script" "")
        local post_script=$(get_path_config "$hostname" "$i" "post_script" "")
        local pre_script_local=$(get_path_config "$hostname" "$i" "pre_script_local" "")
        local post_script_local=$(get_path_config "$hostname" "$i" "post_script_local" "")
        
        # Run pre-script (remote)
        if [[ -n "$pre_script" && "$pre_script" != "null" ]]; then
            run_script "$pre_script" "$ssh_user" "$ssh_key" "remote"
        fi
        
        # Run local pre-script
        if [[ -n "$pre_script_local" && "$pre_script_local" != "null" ]]; then
            run_script "$pre_script_local" "$ssh_user" "$ssh_key" "local"
        fi
        
        # Determine source and destination paths
        local source_path
        local dest_path="$backup_dir"
        
        if [[ -n "$dest_subdir" && "$dest_subdir" != "null" ]]; then
            dest_path="$backup_dir/$dest_subdir"
            if [[ ! -d "$dest_path" ]]; then
                print_info "Creating subdirectory $dest_subdir"
                execute_command "mkdir -p \"$dest_path\""
            fi
        fi
        
        # Handle local vs remote backups
        if [[ -n "$ssh_user" && "$ssh_user" != "null" && "$ssh_user" != '""' ]]; then
            source_path="$ssh_user:$path"
        else
            source_path="$path"
        fi
        
        # Build rsync command with improved permission handling
        local rsync_cmd="/usr/bin/rsync $rsyncOptions"
        
        # Add ownership handling options based on configuration
        if [[ "$preserve_ownership" == "false" ]]; then
            # Map all files to root ownership and fix permissions
            rsync_cmd="$rsync_cmd --no-owner --no-group --chmod=D755,F644"
        else
            # Preserve original ownership but ensure we can write to directories
            rsync_cmd="$rsync_cmd --chmod=Du+w"
        fi
        
        if [[ -n "$path_rsync_path" && "$path_rsync_path" != "null" ]]; then
            rsync_cmd="$rsync_cmd --rsync-path \"$path_rsync_path\""
        fi
        
        if [[ -n "$ssh_key" && "$ssh_key" != "null" && "$ssh_key" != '""' && -n "$ssh_user" ]]; then
            # Add SSH options to handle problematic shells (like fish)
            rsync_cmd="$rsync_cmd -e \"ssh -i $ssh_key -o LogLevel=ERROR -o BatchMode=yes\""
        fi
        
        if [[ -n "$path_options" && "$path_options" != "null" ]]; then
            rsync_cmd="$rsync_cmd $path_options"
        fi
        
        if [[ -n "$path_exclude" && "$path_exclude" != "null" ]]; then
            rsync_cmd="$rsync_cmd --exclude-from $path_exclude"
        fi
        
        print_info "Backing up $hostname:$path -> $dest_path"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            print_dry_run "$rsync_cmd $source_path $dest_path"
            BACKUP_STATUS_VOLUME="success"
        else
            # Ensure backup directory is writable by root before rsync
            if [[ -d "$dest_path" ]]; then
                chmod -R u+w "$dest_path" 2>/dev/null || true
            fi
            
            print_command "$rsync_cmd $source_path $dest_path"
            
            # Capture rsync output and statistics
            local rsync_output_file="/tmp/rsync_output_${hostname}_${i}_$$.log"
            eval "$rsync_cmd $source_path $dest_path" 2>&1 | tee "$rsync_output_file"
            local rsync_exit_code=${PIPESTATUS[0]}
            
            # Extract rsync statistics from output
            local bytes_sent=$(grep "sent.*bytes" "$rsync_output_file" | sed -n 's/sent \([0-9.]*\) bytes.*/\1/p' | tr -d '.')
            local bytes_received=$(grep "received.*bytes" "$rsync_output_file" | sed -n 's/.*received \([0-9.]*\) bytes.*/\1/p' | tr -d '.')
            local transfer_rate=$(grep "bytes/sec" "$rsync_output_file" | sed -n 's/.*\([0-9.,]*\) bytes\/sec/\1/p' | tr -d ',.')
            local total_size=$(grep "total size is" "$rsync_output_file" | sed -n 's/total size is \([0-9.]*\).*/\1/p' | tr -d '.')
            local speedup=$(grep "speedup is" "$rsync_output_file" | sed -n 's/.*speedup is \([0-9.,]*\)/\1/p' | tr -d ',')
            
            # Extract detailed error information for better Grafana display
            local error_count=$(grep -c "rsync:" "$rsync_output_file" || echo "0")
            local warning_count=$(grep -c "warning\|partial transfer" "$rsync_output_file" || echo "0")
            local permission_errors=$(grep -c "Permission denied" "$rsync_output_file" || echo "0")
            local connection_errors=$(grep -c "connection\|timeout\|refused" "$rsync_output_file" || echo "0")
            
            # Extract first few error messages for detailed logging
            local error_messages=""
            if [[ $error_count -gt 0 ]]; then
                error_messages=$(grep "rsync:" "$rsync_output_file" | head -3 | tr '\n' '; ' | sed 's/; $//')
            fi
            
            # Log enhanced rsync statistics for metrics collection
            echo "RSYNC_STATS: host=$hostname path=$path bytes_sent=$bytes_sent bytes_received=$bytes_received transfer_rate=$transfer_rate total_size=$total_size speedup=$speedup exit_code=$rsync_exit_code error_count=$error_count warning_count=$warning_count permission_errors=$permission_errors connection_errors=$connection_errors timestamp=$(date '+%Y-%m-%d %H:%M:%S')" >> /var/log/backup-stats.log
            
            # Log detailed error messages if any exist
            if [[ -n "$error_messages" ]]; then
                echo "RSYNC_ERRORS: host=$hostname path=$path messages=\"$error_messages\" timestamp=$(date '+%Y-%m-%d %H:%M:%S')" >> /var/log/backup-stats.log
            fi
            
            # Clean up temporary file
            rm -f "$rsync_output_file" 2>/dev/null
            
            # Fix permissions after rsync if preserve_ownership is false
            if [[ "$preserve_ownership" == "false" ]]; then
                print_info "Fixing ownership and permissions for backup files..."
                chown -R root:root "$dest_path" 2>/dev/null || true
                find "$dest_path" -type d -exec chmod 755 {} \; 2>/dev/null || true
                find "$dest_path" -type f -exec chmod 644 {} \; 2>/dev/null || true
            else
                # Just ensure directories are writable for future backups
                find "$dest_path" -type d -exec chmod u+w {} \; 2>/dev/null || true
            fi
            
            # Interpret rsync exit code
            BACKUP_STATUS_VOLUME=$(interpret_rsync_exit_code $rsync_exit_code "backup")
            
            # Log rsync result with proper exit code interpretation
            case "$BACKUP_STATUS_VOLUME" in
                "success")
                    print_success "Volume backup completed successfully: $hostname:$path"
                    ;;
                "warning")
                    print_warning "Volume backup completed with warnings: $hostname:$path (exit code: $rsync_exit_code)"
                    # Log specific error for metrics collection
                    if [[ $error_count -gt 0 ]]; then
                        echo "BACKUP_ERROR: host=$hostname path=$path error_count=$error_count exit_code=$rsync_exit_code timestamp=$(date '+%Y-%m-%d %H:%M:%S')" >&2
                    fi
                    # Don't fail the host for warnings, but track it
                    if [[ "$BACKUP_STATUS_HOST" == "success" ]]; then
                        BACKUP_STATUS_HOST="warning"
                    fi
                    ;;
                "failed")
                    print_error "Volume backup failed: $hostname:$path (exit code: $rsync_exit_code)"
                    # Log specific error for metrics collection
                    echo "BACKUP_ERROR: host=$hostname path=$path error_count=$error_count exit_code=$rsync_exit_code timestamp=$(date '+%Y-%m-%d %H:%M:%S')" >&2
                    BACKUP_STATUS_HOST="failed"
                    BACKUP_STATUS_OVERALL="failed"
                    ;;
            esac
        fi
        
        # Run local post-script
        if [[ -n "$post_script_local" && "$post_script_local" != "null" ]]; then
            run_script "$post_script_local" "$ssh_user" "$ssh_key" "local"
        fi
        
        # Run post-script (remote)
        if [[ -n "$post_script" && "$post_script" != "null" ]]; then
            run_script "$post_script" "$ssh_user" "$ssh_key" "remote"
        fi
    done
    
    # Log final host backup status
    if [[ "$BACKUP_STATUS_HOST" == "success" ]]; then
        print_success "Host backup completed successfully: $hostname"
    elif [[ "$BACKUP_STATUS_HOST" == "warning" ]]; then
        print_warning "Host backup completed with warnings: $hostname"
        # Track overall warning status
        if [[ "$BACKUP_STATUS_OVERALL" == "success" ]]; then
            BACKUP_STATUS_OVERALL="warning"
        fi
    else
        print_error "Host backup failed: $hostname"
        BACKUP_STATUS_OVERALL="failed"
    fi
}

function verify_host_connectivity() {
    local hostname="$1"
    local ssh_user="$2" 
    local ssh_key="$3"
    local ignore_ping="$4"
    local allow_interactive="${5:-false}"
    
    print_info "Verifying connectivity to $hostname..."
    
    # In dry-run mode, just simulate the verification
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$ignore_ping" != "true" ]]; then
            print_dry_run "ping -c 1 -W 3 \"$hostname\""
        else
            print_info "Skipping ping for $hostname (ignore_ping=true)"
        fi
        
        if [[ -n "$ssh_user" && "$ssh_user" != "null" && "$ssh_user" != '""' ]]; then
            local ssh_cmd="ssh"
            if [[ -n "$ssh_key" && "$ssh_key" != "null" && "$ssh_key" != '""' ]]; then
                ssh_cmd="$ssh_cmd -i $ssh_key"
            fi
            ssh_cmd="$ssh_cmd -o ConnectTimeout=10 -o BatchMode=yes"
            print_dry_run "$ssh_cmd $ssh_user \"echo 'Connection successful'\""
        else
            print_info "Local backup - no SSH verification needed"
        fi
        print_success "Would verify connection to $hostname"
        return 0
    fi
    
    # Extract hostname from ssh_user if it contains @
    local target_host="$hostname"
    if [[ "$ssh_user" == *"@"* ]]; then
        target_host="${ssh_user##*@}"
    fi
    
    # Check if we should skip ping
    if [[ "$ignore_ping" == "true" ]]; then
        print_info "Skipping ping for $target_host (ignore_ping=true)"
    else
        # First check if host is reachable via ping
        echo -e "  ${BLUE}Checking if $target_host is reachable...${NC}"
        if ! ping -c 1 -W 3 "$target_host" &>/dev/null; then
            print_error "Host $target_host is not reachable (ping failed)"
            return 1
        fi
        echo -e "  ${GREEN}✓${NC} Host $target_host is reachable"
    fi
    
    # For local backups (empty ssh_user), skip SSH verification
    if [[ -z "$ssh_user" || "$ssh_user" == "null" || "$ssh_user" == '""' ]]; then
        print_success "Local backup - no SSH verification needed"
        return 0
    fi
    
    # Build SSH command
    local ssh_cmd="ssh"
    if [[ -n "$ssh_key" && "$ssh_key" != "null" && "$ssh_key" != '""' ]]; then
        ssh_cmd="$ssh_cmd -i $ssh_key"
    fi
    ssh_cmd="$ssh_cmd -o ConnectTimeout=10 -o BatchMode=yes"
    
    print_command "$ssh_cmd $ssh_user \"echo 'Connection successful'\""
    
    # Test connection
    if $ssh_cmd "$ssh_user" "echo 'Connection successful'" &>/dev/null; then
        print_success "Successfully connected to $hostname"
        return 0
    else
        print_error "Failed to connect to $hostname via SSH"
        
        # Only offer interactive SSH key setup if allowed
        if [[ "$allow_interactive" == "true" ]]; then
            echo -e "${YELLOW}Would you like to setup SSH key for $hostname? (y/N):${NC} " 
            read -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_ssh_key "$ssh_user" "$ssh_key"
                return $?
            else
                return 1
            fi
        else
            print_info "Suggestion: Run '$0 --verify-hosts' interactively to setup SSH keys"
            return 1
        fi
    fi
}

function setup_ssh_key() {
    local ssh_user="$1"
    local ssh_key="$2"
    
    print_info "Setting up SSH key for $ssh_user..."
    
    # Check if key exists
    if [[ ! -f "$ssh_key" ]]; then
        print_warning "SSH key $ssh_key not found. Generating new key..."
        print_command "ssh-keygen -t ed25519 -f \"$ssh_key\" -N \"\""
        ssh-keygen -t ed25519 -f "$ssh_key" -N ""
    fi
    
    # Copy key to remote host
    print_info "Copying SSH key to remote host..."
    print_command "ssh-copy-id -i \"$ssh_key\" \"$ssh_user\""
    ssh-copy-id -i "$ssh_key" "$ssh_user"
    
    # Verify connection again
    print_info "Verifying SSH key setup..."
    if ssh -i "$ssh_key" -o ConnectTimeout=10 -o BatchMode=yes "$ssh_user" "echo 'Key setup successful'" &>/dev/null; then
        print_success "SSH key setup successful for $ssh_user"
        return 0
    else
        print_error "SSH key setup failed for $ssh_user"
        return 1
    fi
}

function verify_all_hosts() {
    local allow_interactive="${1:-false}"
    
    print_header "Verifying connectivity to all configured hosts"
    
    local failed_hosts=()
    local working_hosts=()
    
    for hostname in "${BACKUP_HOSTS[@]}"; do
        local ssh_key=$(get_host_config "$hostname" "ssh_key" "/home/pjakobs/.ssh/id_ed25519")
        local ssh_user_raw=$(get_host_config "$hostname" "ssh_user" "pjakobs")
        local target_hostname=$(get_host_config "$hostname" "hostname" "$hostname")
        local ignore_ping=$(get_host_config "$hostname" "ignore_ping" "false")
        
        # Handle both formats: combined "user@host" or separate fields
        local ssh_user
        if [[ "$ssh_user_raw" == *"@"* ]]; then
            # Already has user@host format
            ssh_user="$ssh_user_raw"
        elif [[ -n "$ssh_user_raw" && "$ssh_user_raw" != "null" && "$ssh_user_raw" != '""' ]]; then
            # Separate user and hostname fields
            ssh_user="$ssh_user_raw@$target_hostname"
        else
            # Local backup (empty ssh_user)
            ssh_user=""
        fi
        
        if [[ "$DRY_RUN" != "true" ]]; then
            print_info "Debug: hostname='$hostname', target='$target_hostname', ssh_user='$ssh_user', ssh_key='$ssh_key', ignore_ping='$ignore_ping'"
        fi
        
        if verify_host_connectivity "$hostname" "$ssh_user" "$ssh_key" "$ignore_ping" "$allow_interactive"; then
            working_hosts+=("$hostname")
        else
            failed_hosts+=("$hostname")
        fi
    done
    print_info "Verification complete. Working hosts: ${working_hosts[*]}"
    print_info "Failed hosts: ${failed_hosts[*]}"
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "Would fail to connect to: ${failed_hosts[*]} (but continuing dry run)"
        else
            print_warning "Failed to connect to: ${failed_hosts[*]}"
            if [[ ${#working_hosts[@]} -gt 0 ]]; then
                print_info "Will continue with working hosts: ${working_hosts[*]}"
                # Update BACKUP_HOSTS to only include working hosts
                BACKUP_HOSTS=("${working_hosts[@]}")
                return 0
            else
                print_error "No hosts are available for backup"
                return 1
            fi
        fi
    fi
}

function create_snapshots() {
    local snapshot_volume=$(yq eval '.snapshots.volume // "/share"' "$CONFIG_FILE")
    local schedules_count=$(yq eval '.snapshots.schedules | length' "$CONFIG_FILE")
    
    print_header "Creating BTRFS Snapshots"
    
    if [[ "$schedules_count" == "0" || "$schedules_count" == "null" ]]; then
        print_warning "No snapshot schedules configured, using defaults..."
        # Use original values as fallback
        execute_command "sudo /usr/local/sbin/btrfs-snp /share hourly 6 14400"
        execute_command "sudo /usr/local/sbin/btrfs-snp /share daily 7 86400"
        execute_command "sudo /usr/local/sbin/btrfs-snp /share weekly 4 604800"
        execute_command "sudo /usr/local/sbin/btrfs-snp /share monthly 12 2592000"
        execute_command "sudo /usr/local/sbin/btrfs-snp /share yearly 4 31536000"
        return
    fi
    
    print_info "Creating BTRFS snapshots for $snapshot_volume..."
    
    for ((i=0; i<schedules_count; i++)); do
        local type=$(yq eval ".snapshots.schedules[$i].type" "$CONFIG_FILE")
        local count=$(yq eval ".snapshots.schedules[$i].count" "$CONFIG_FILE")
        local interval=$(yq eval ".snapshots.schedules[$i].interval" "$CONFIG_FILE")
        
        if [[ "$type" != "null" && "$count" != "null" && "$interval" != "null" ]]; then
            print_info "Creating $type snapshots: $count snapshots, $interval second intervals"
            execute_command "sudo /usr/local/sbin/btrfs-snp \"$snapshot_volume\" \"$type\" \"$count\" \"$interval\""
        else
            print_warning "Skipping snapshot schedule $i due to missing configuration"
        fi
    done
}

trap ctrl_c INT

# Function to show help
show_help() {
    print_header "Backup Script Help"
    echo -e "${WHITE}Usage:${NC} $0 [OPTIONS]"
    echo
    echo -e "${WHITE}Options:${NC}"
    echo -e "  ${CYAN}--verify-hosts${NC}    Verify SSH connectivity to all configured hosts"
    echo -e "  ${CYAN}--dry-run${NC}         Show what would be executed without running commands"
    echo -e "  ${CYAN}--backup${NC}          Run the actual backup process"
    echo -e "  ${CYAN}--help, -h${NC}        Show this help message"
    echo
    echo -e "${WHITE}Examples:${NC}"
    echo -e "  $0 --verify-hosts    # Test connectivity to all hosts"
    echo -e "  $0 --dry-run         # Preview what backup would do"
    echo -e "  $0 --backup          # Run the backup"
    exit 0
}

# Function to run backup operations
run_backup() {
    local dry_run_mode="$1"
    
    if [[ "$dry_run_mode" == "true" ]]; then
        DRY_RUN=true
        print_dry_run "backup would be executed without making changes"
        echo
    else
        DRY_RUN=false
        print_header "Backup Script - LIVE MODE"
        print_info "This will execute actual backup operations"
        echo
    fi
    
    check_dependencies
    
    # Initialize overall backup status
    BACKUP_STATUS_OVERALL="success"
    
    # Load configuration
    backup_base=$(get_config_value "backup_base" "/share/backup/")
    lock_file=$(get_config_value "lock_file" "/tmp/backup.fil")
    rsyncOptions=$(get_config_value "rsync_options" "$rsyncOptions")
    
    print_info "Using rsync options: $rsyncOptions"
    
    # Handle lock file and create snapshots
    if [[ "$dry_run_mode" == "true" ]]; then
        print_dry_run "echo \$\$ > \"$lock_file\""
        print_dry_run "create_snapshots"
    else
        if ! check_lock_file "$lock_file"; then
            exit 1
        fi
        execute_command "echo \$\$ > \"$lock_file\""
        create_snapshots
    fi
    
    # Parse configuration
    parse_yaml "$CONFIG_FILE"
    
    # Verify all hosts before starting backup (non-interactive for unattended runs)
    if ! verify_all_hosts "false"; then
        print_error "Host verification failed. Use --verify-hosts to fix connectivity issues."
        if [[ "$dry_run_mode" == "true" ]]; then
            print_dry_run "rm \"$lock_file\""
        else
            execute_command "rm \"$lock_file\""
        fi
        exit 1
    fi
    
    if [[ "$dry_run_mode" == "true" ]]; then
        print_header "Starting Backup Operations (DRY RUN)"
        #print_dry_run "job_pool_init $(nproc) 0"
        print_info "Would initialize job pool with $(nproc) parallel jobs"
    else
        print_header "Starting Backup Operations"
        print_info "Initializing job pool with $(nproc) parallel jobs"
        #job_pool_init $(nproc) 0 # use number of system installed cores as max job number
    fi
    
    # Backup each host
    for hostname in "${BACKUP_HOSTS[@]}"; do
        backup_host "$hostname"
    done
    
    if [[ "$dry_run_mode" == "true" ]]; then
        #print_dry_run "job_pool_shutdown"
        print_info "Would shutdown job pool"
        print_dry_run "rm \"$lock_file\""
        print_success "Dry run completed successfully"
    else
        #job_pool_shutdown
        execute_command "rm \"$lock_file\""
        
        # Report final backup status
        if [[ "$BACKUP_STATUS_OVERALL" == "success" ]]; then
            print_success "Backup operations completed successfully"
        elif [[ "$BACKUP_STATUS_OVERALL" == "warning" ]]; then
            print_warning "Backup operations completed with warnings"
        else
            print_error "Backup operations completed with failures"
            exit 1
        fi
    fi
}

# Main execution
case "${1:-}" in
    "--verify-hosts")
        check_dependencies
        parse_yaml "$CONFIG_FILE"
        verify_all_hosts "true"  # Allow interactive SSH key setup
        exit $?
        ;;
    "--dry-run")
        run_backup "true"
        ;;
    "--backup")
        trap ctrl_c INT
        run_backup "false"
        ;;
    "--help"|"-h")
        show_help
        ;;
    "")
        # No arguments - show help
        show_help
        ;;
    *)
        print_error "Unknown option: $1"
        echo
        show_help
        ;;
esac
