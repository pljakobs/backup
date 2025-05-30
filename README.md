# Enhanced Backup System

This comprehensive backup system provides automated, parallel backups with BTRFS snapshot support, comprehensive configuration management, and advanced monitoring capabilities including Grafana dashboards and InfluxDB integration.

## System Components

### 1. Backup Script (`backup-new.sh`)
The main backup execution script with YAML configuration support.

### 2. Metrics Collector (`backup-metrics`)
Advanced Python-based metrics collection and monitoring system with InfluxDB integration.

### 3. Grafana Dashboard (`dashboard-cleaned-up.json`)
Pre-configured dashboard for monitoring backup status, performance, and errors.

## Features Overview

### Backup Script Features

#### Configuration-Driven Operations
- **YAML Configuration**: All backup settings in `/etc/backup/backup.yaml`
- **Per-host Configuration**: Individual SSH keys, users, paths, and options
- **Path-level Customization**: Different rsync options per path
- **Script Integration**: Pre/post scripts for each host and path

#### Advanced Backup Capabilities
- **Parallel Processing**: Multi-threaded backup execution
- **Permission Management**: Configurable ownership preservation
- **Enhanced Error Handling**: Detailed rsync exit code interpretation
- **Dry-run Mode**: Preview operations without execution
- **BTRFS Snapshots**: Automated snapshot creation with configurable schedules

#### Connectivity & Verification
- **Host Verification**: Test SSH connectivity before backup
- **Automatic SSH Setup**: Interactive SSH key installation
- **Connection Resilience**: Skip unreachable hosts and continue

### Metrics System Features

#### Intelligent Log Analysis
- **Session Extraction**: Parse complete backup sessions from systemd logs
- **Status Detection**: Automatic success/warning/failure classification
- **Error Tracking**: Capture and categorize rsync errors
- **Performance Metrics**: Transfer rates, speedup ratios, file counts

#### Backup Frequency Auto-Detection
- **Timer Analysis**: Reads systemd timer configurations (`*-*-* 00/2:00:00` format)
- **Pattern Recognition**: Detects hourly, daily, weekly schedules
- **Adaptive Search**: Automatically adjusts log search timeframe
- **Fallback Logic**: Uses actual backup intervals if timer info unavailable

#### Directory Size Monitoring
- **Background Scanning**: Non-blocking directory size calculation
- **BTRFS Optimization**: Uses `btrfs filesystem du` for better performance
- **Progressive Updates**: Real-time InfluxDB updates as scans complete
- **Timeout Protection**: Prevents hanging on large directories

#### Multi-Database Support
- **InfluxDB 2.x**: Token-based authentication with organizations and buckets
- **InfluxDB 1.x**: Username/password authentication with databases
- **Auto-Detection**: Automatically selects appropriate API version
- **Configuration Testing**: Built-in connection and authentication verification

### Grafana Dashboard Features

#### Real-time Monitoring
- **Overall Status**: Visual backup health indicators
- **Host-level Details**: Individual host backup status and sizes
- **Volume-level Tracking**: Per-path backup results with exit codes
- **Error Display**: Detailed error and warning messages

#### Performance Analytics
- **Duration Trends**: Backup time analysis over time
- **Transfer Statistics**: Bytes sent/received, transfer rates
- **Storage Growth**: Total backup size tracking
- **Efficiency Metrics**: Rsync speedup ratios

## Installation & Setup

### 1. Install Dependencies

The backup script will automatically detect and offer to install missing dependencies:

```bash
# For Ubuntu/Debian
sudo apt update && sudo apt install -y yq python3 python3-pip

# Install Python dependencies
pip3 install pyyaml requests

# Install optional dependencies
sudo curl -o /usr/local/sbin/btrfs-snp https://raw.githubusercontent.com/nachoparker/btrfs-snp/refs/heads/master/btrfs-snp
sudo chmod +x /usr/local/sbin/btrfs-snp
```

### 2. Configuration Setup

Create the main configuration file:

```bash
sudo mkdir -p /etc/backup
sudo cp backup.yaml.example /etc/backup/backup.yaml
```

Example configuration structure:

```yaml
config:
  backup_base: "/share/backup/"
  lock_file: "/tmp/backup.fil"
  rsync_options: "-avz --delete --numeric-ids --stats --human-readable"

hosts:
  server1:
    ssh_user: "backup"
    ssh_key: "/root/.ssh/backup_key"
    hostname: "server1.example.com"
    preserve_ownership: false
    paths:
      - path: "/etc"
        dest_subdir: "etc"
      - path: "/home"
        dest_subdir: "home"
        exclude_file: "/etc/backup/excludes/home.txt"

  server2:
    ssh_user: "root@server2.local"
    ignore_ping: true
    paths:
      - path: "/var/www"
        dest_subdir: "www"
        pre_script: "stop_apache"
        post_script: "start_apache"

snapshots:
  volume: "/share"
  schedules:
    - type: "hourly"
      count: 6
      interval: 14400
    - type: "daily" 
      count: 7
      interval: 86400
```

### 3. InfluxDB Configuration

Create InfluxDB configuration:

```bash
sudo cp influxdb-config.yaml.example /etc/backup/influxdb-config.yaml
```

For InfluxDB 2.x:

```yaml
influxdb:
  host: "localhost"
  port: 8086
  ssl: false
  token: "your-influxdb-token"
  organization: "home"
  bucket: "backup"
```

For InfluxDB 1.x:

```yaml
influxdb:
  host: "localhost"
  port: 8086
  ssl: false
  database: "backup_metrics"
  username: "backup_user"
  password: "backup_password"
```

### 4. Systemd Timer Setup

Create systemd service and timer:

```bash
# /etc/systemd/system/backup.service
[Unit]
Description=Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/backup-new.sh --backup
User=root

# /etc/systemd/system/backup.timer
[Unit]
Description=Timer for Backup task

[Timer]
OnCalendar=*-*-* 00/2:00:00
Persistent=yes

[Install]
WantedBy=timers.target
```

Enable the timer:

```bash
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
```

## Usage Examples

### Backup Script Operations

```bash
# Verify connectivity to all hosts
./backup-new.sh --verify-hosts

# Preview what backup would do
./backup-new.sh --dry-run

# Run actual backup
./backup-new.sh --backup

# Get help
./backup-new.sh --help
```

### Metrics Collection

```bash
# Basic metrics collection (auto-detects backup frequency)
./backup-metrics

# Show last backup run logs
./backup-metrics --last-run

# Show 3rd last backup run
./backup-metrics --last-run -2

# Show last 3 backup runs
./backup-metrics --last-run --count 3

# Filter logs for specific host
./backup-metrics --last-run --host server1

# Search specific time range
./backup-metrics --last-run --hours 48

# Complex example: Show 4 runs starting from 5th last, for specific host
./backup-metrics --last-run -4 --count 4 --host server1

# Send metrics to InfluxDB immediately
./backup-metrics --send-influxdb

# Send metrics after directory scan completes
./backup-metrics --send-influxdb-wait

# Test InfluxDB connection
./backup-metrics --test-influxdb

# Query existing data from InfluxDB
./backup-metrics --query-data 48

# Enable verbose debugging
./backup-metrics --verbose --last-run
```

### InfluxDB Integration

```bash
# Test database connection
./backup-metrics --test-influxdb

# Send current metrics
./backup-metrics --send-influxdb

# Query recent data
./backup-metrics --query-data 24

# View JSON output
./backup-metrics --json
```

## Monitoring & Dashboards

### Grafana Dashboard Import

1. Import the dashboard JSON: `dashboard-cleaned-up.json`
2. Configure InfluxDB data source
3. The dashboard includes:
   - Overall backup status with color-coded health indicators
   - Host-level status table with sizes and last run times
   - Volume-level details with exit codes and error messages
   - Performance trends and duration analytics

### Key Metrics

The system tracks and visualizes:

- **status_numeric**: 1.0 = success, 0.5 = warning, 0.0 = failed
- **error_count**: Number of errors in last backup
- **duration_seconds**: Backup execution time
- **total_size_bytes**: Total backup storage used
- **transfer_rate**: Rsync transfer speed (bytes/sec)
- **speedup**: Rsync efficiency ratio

### Alerting

Set up Grafana alerts based on:
- `status_numeric < 1.0` (backup failures/warnings)
- `error_count > 0` (errors detected)
- `duration_seconds > threshold` (backups taking too long)
- Missing data (backup not running)

## Advanced Features

### Frequency Auto-Detection

The metrics system automatically detects backup frequency by:

1. **Reading systemd timers**: Parses `OnCalendar` specifications like `*-*-* 00/2:00:00`
2. **Analyzing intervals**: Calculates average time between actual backup runs
3. **Adaptive search**: Adjusts log search timeframe (6 hours for 2-hourly, 48 hours for daily)

### Error Classification

The system categorizes backup issues:

- **Rsync Exit Codes**: Maps to success/warning/failed status
- **Error Types**: Permission errors, connection timeouts, protocol errors
- **Warning Conditions**: Partial transfers, vanished files
- **Performance Issues**: Slow transfers, low speedup ratios

### Background Processing

- **Non-blocking scans**: Directory size calculation runs in background
- **Real-time updates**: InfluxDB receives updates as hosts are scanned
- **Timeout protection**: Prevents hanging on network filesystems
- **Progressive monitoring**: Dashboard updates continuously during scans

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**
   ```bash
   # Use verify-hosts to diagnose and fix
   ./backup-new.sh --verify-hosts
   ```

2. **InfluxDB Connection Problems**
   ```bash
   # Test connection and configuration
   ./backup-metrics --test-influxdb
   ```

3. **Missing Backup Data**
   ```bash
   # Check if backups are running
   systemctl status backup.timer
   
   # View recent logs
   ./backup-metrics --last-run --verbose
   ```

4. **Permission Issues**
   ```bash
   # Check backup directory permissions
   ls -la /share/backup/
   
   # Verify rsync can write to destination
   ```

### Log Analysis

```bash
# View systemd logs
journalctl -u backup.service -f

# Check backup statistics log
tail -f /var/log/backup-stats.log

# Analyze specific backup session
./backup-metrics --last-run --verbose
```

## Development & Customization

### Adding New Hosts

1. Add to `backup.yaml`:
   ```yaml
   hosts:
     new_host:
       ssh_user: "user@new_host.com"
       paths:
         - path: "/data"
   ```

2. Verify connectivity:
   ```bash
   ./backup-new.sh --verify-hosts
   ```

### Custom Scripts

Add pre/post scripts in `/etc/backup/scripts/`:

```bash
# /etc/backup/scripts/stop_service.sh
systemctl stop myservice

# Reference in configuration
paths:
  - path: "/data"
    pre_script: "stop_service"
    post_script: "start_service"
```

### Extending Metrics

The metrics system can be extended with additional measurements by modifying the InfluxDB line protocol generation in `backup-metrics`.

---

This backup system provides enterprise-grade backup capabilities with comprehensive monitoring, making it suitable for both home labs and production environments.
