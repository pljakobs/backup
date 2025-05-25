# Enhanced Backup Script

This backup script provides automated, parallel backups with BTRFS snapshot support and comprehensive configuration management.

## New Features

### 1. Configuration-Driven Snapshots
- Snapshot schedules are now configurable via YAML
- Configurable target volume
- Fallback to defaults if no configuration is provided

### 2. Automatic Dependency Management
- Automatically detects missing dependencies (`yq`, `btrfs-snp`, `job_pool.sh`)
- Offers to install missing dependencies with user confirmation
- Downloads `job_pool.sh` automatically if missing

### 3. Host Verification Mode
- New `--verify-hosts` command line option
- Tests SSH connectivity to all configured hosts
- Automatically sets up SSH keys for unreachable hosts
- Runs `ssh-copy-id` when needed

### 4. Configurable Backup Directories
- Backup base directory now configurable via YAML
- Lock file location configurable
- Rsync options configurable globally and per-path

## Usage

### Basic Backup
```bash
./backup-new.sh
```

### Verify Host Connectivity
```bash
./backup-new.sh --verify-hosts
```

### Help
```bash
./backup-new.sh --help
```

## Configuration

Copy `backup.yaml.example` to `/etc/backup/backup.yaml` and modify as needed:

```yaml
config:
  backup_base: "/share/backup/"
  lock_file: "/tmp/backup.fil"
  rsync_options: "-avz --delete --numeric-ids"

snapshots:
  volume: "/share"
  schedules:
    - type: "hourly"
      count: 6
      interval: 14400

hosts:
  server1:
    ssh_user: "user@server1"
    ssh_key: "/home/user/.ssh/id_ed25519"
    paths:
      - path: "/home"
        dest_subdir: "home"
```

## Configuration Options

### Global Config
- `backup_base`: Base directory for all backups
- `lock_file`: Lock file to prevent concurrent runs
- `rsync_options`: Default rsync options

### Snapshot Config
- `volume`: BTRFS volume to snapshot
- `schedules`: Array of snapshot schedules
  - `type`: hourly, daily, weekly, monthly, yearly
  - `count`: Number of snapshots to retain
  - `interval`: Interval in seconds

### Host Config
- `ssh_user`: SSH user@hostname for remote connections
- `ssh_key`: Path to SSH private key
- `exclude_file`: Global exclude file for this host
- `rsync_path`: Custom rsync path on remote host
- `paths`: Array of paths to backup

### Path Config
- `path`: Source path to backup
- `dest_subdir`: Destination subdirectory
- `exclude_file`: Path-specific exclude file
- `rsync_path`: Path-specific rsync command
- `host_options`: Additional rsync options for this path
- `pre_script`: Remote script to run before backup
- `post_script`: Remote script to run after backup
- `pre_script_local`: Local script to run before backup
- `post_script_local`: Local script to run after backup

## Dependencies

- `yq`: YAML processor
- `btrfs-snp`: BTRFS snapshot utility
- `job_pool.sh`: Parallel job execution
- Standard tools: `rsync`, `ssh`, `ssh-copy-id`, `ssh-keygen`

## Error Handling

- Automatic host verification before backup starts
- Graceful handling of missing dependencies
- Lock file prevents concurrent execution
- Signal handling for clean shutdown

## Security Features

- SSH key verification and setup
- Automatic host key acceptance prompts
- Support for custom SSH keys per host
- Batch mode testing for automated environments
