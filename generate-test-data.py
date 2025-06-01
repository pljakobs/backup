#!/usr/bin/env python3
"""
Generate test data for backup testing and metrics.
This script creates realistic sample data for both host-level and volume-level metrics,
and can also generate file system test data for client containers.
"""

import sys
import os
import yaml
import random
import argparse
from datetime import datetime, timedelta
from pathlib import Path

try:
    from influxdb_client import InfluxDBClient, Point
    from influxdb_client.client.write_api import SYNCHRONOUS
    INFLUX_AVAILABLE = True
except ImportError:
    INFLUX_AVAILABLE = False
    print("Warning: InfluxDB client not available, metrics generation disabled")

def generate_filesystem_data(client_id, data_size="medium"):
    """Generate filesystem test data for a client."""
    base_path = Path("/home/testuser/data")
    base_path.mkdir(parents=True, exist_ok=True)
    
    # Create client-specific directories
    dirs = [
        "documents", "photos", "config", "logs", 
        f"client{client_id}_specific", "shared", "backup_test"
    ]
    
    for dir_name in dirs:
        (base_path / dir_name).mkdir(exist_ok=True)
    
    # Size configurations
    size_configs = {
        "small": {"files": 50, "max_size": 1024*100},      # 100KB max
        "medium": {"files": 200, "max_size": 1024*1024},   # 1MB max  
        "large": {"files": 500, "max_size": 1024*1024*10}, # 10MB max
    }
    
    config = size_configs.get(data_size, size_configs["medium"])
    
    # Generate files with client-specific content
    for i in range(config["files"]):
        # Distribute files across directories
        dir_name = random.choice(dirs)
        file_path = base_path / dir_name / f"file_{client_id}_{i:03d}.txt"
        
        # Generate random content
        size = random.randint(100, config["max_size"])
        content = f"Client {client_id} test file {i}\n"
        content += f"Generated at: {datetime.now()}\n"
        content += f"File size: {size} bytes\n"
        content += "=" * 50 + "\n"
        
        # Add random data to reach target size
        remaining = size - len(content.encode())
        if remaining > 0:
            content += "Random data: " + "x" * (remaining - 13) + "\n"
        
        with open(file_path, 'w') as f:
            f.write(content)
    
    # Create some large files for realistic backup scenarios
    if data_size in ["medium", "large"]:
        large_files = 3 if data_size == "medium" else 10
        for i in range(large_files):
            file_path = base_path / "documents" / f"large_client{client_id}_{i}.dat"
            size = random.randint(1024*1024, config["max_size"])
            
            with open(file_path, 'wb') as f:
                # Write in chunks to avoid memory issues
                chunk_size = 8192
                written = 0
                while written < size:
                    chunk = os.urandom(min(chunk_size, size - written))
                    f.write(chunk)
                    written += len(chunk)
    
    print(f"Generated {config['files']} files for client{client_id} (size: {data_size})")

def load_config():
    """Load configuration files."""
    try:
        # Load backup config
        with open('/etc/backup/backup.yaml', 'r') as f:
            backup_config = yaml.safe_load(f)
        
        # Load InfluxDB config  
        with open('/etc/backup/influxdb-config.yaml', 'r') as f:
            influx_config = yaml.safe_load(f)
        
        return backup_config, influx_config
    except Exception as e:
        print(f"Error loading config: {e}")
        return None, None

def generate_rsync_stats():
    """Generate realistic rsync statistics."""
    total_size = random.randint(1024*1024*100, 1024*1024*1024*5)  # 100MB to 5GB
    bytes_sent = random.randint(total_size//100, total_size//10)  # 1-10% of total
    bytes_received = random.randint(1024, 1024*1024)  # Small metadata
    transfer_rate = random.randint(1024*1024*5, 1024*1024*50)  # 5-50 MB/s
    speedup = total_size / max(bytes_sent, 1)  # Realistic speedup ratio
    
    return {
        'total_size': total_size,
        'bytes_sent': bytes_sent,
        'bytes_received': bytes_received,
        'transfer_rate': transfer_rate,
        'speedup': speedup
    }

def generate_test_data(backup_config, influx_config):
    """Generate comprehensive test data for the dashboard."""
    
    if not INFLUX_AVAILABLE:
        print("Error: InfluxDB client not available")
        return
    
    # Create InfluxDB client
    client = InfluxDBClient(
        url=influx_config['influxdb']['url'],
        token=influx_config['influxdb']['token'],
        org=influx_config['influxdb']['org']
    )
    
    write_api = client.write_api(write_options=SYNCHRONOUS)
    
    # Get hosts and volumes from config
    hosts = backup_config.get('hosts', {})
    
    # Generate timestamps for the last 24 hours
    now = datetime.utcnow()
    timestamps = [now - timedelta(hours=i) for i in range(24, 0, -1)]
    
    total_hosts = len(hosts)
    total_volumes = sum(len(host_config.get('paths', [])) for host_config in hosts.values())
    total_errors = 0
    total_duration = 0
    total_size = 0
    
    print(f"Generating data for {total_hosts} hosts, {total_volumes} volumes...")
    
    for timestamp in timestamps:
        # Random success probability for this time period
        success_prob = random.uniform(0.7, 0.95)
        
        for host_name, host_config in hosts.items():
            volumes = host_config.get('paths', [])
            
            # Host-level backup status
            if success_prob > 0.8:
                host_status = 1.0
                host_duration = random.randint(60, 300)  # 1-5 minutes
                host_errors = 0
            elif success_prob > 0.5:
                host_status = 0.5
                host_duration = random.randint(300, 900)  # 5-15 minutes
                host_errors = random.randint(0, 2)
            else:
                host_status = 0.0
                host_duration = random.randint(900, 1800)  # 15-30 minutes
                host_errors = random.randint(1, 5)
            
            total_errors += host_errors
            total_duration += host_duration
            
            # Generate host rsync stats
            host_rsync_stats = generate_rsync_stats()
            total_size += host_rsync_stats['total_size']
            
            # Write host status
            point = Point("backup_host_status") \
                .tag("host", host_name) \
                .field("status_numeric", host_status) \
                .field("bytes_sent", host_rsync_stats['bytes_sent']) \
                .field("bytes_received", host_rsync_stats['bytes_received']) \
                .field("transfer_rate", host_rsync_stats['transfer_rate']) \
                .field("total_size", host_rsync_stats['total_size']) \
                .field("speedup", host_rsync_stats['speedup']) \
                .field("duration_seconds", host_duration) \
                .field("error_count", host_errors) \
                .time(timestamp)
            
            write_api.write(bucket=influx_config['influxdb']['bucket'], record=point)
            
            # Generate volume-level data
            for volume in volumes:
                volume_path = volume.get('path', f"/data/{host_name}")
                
                # Volume status based on host status with some variance
                volume_success_prob = success_prob + random.uniform(-0.2, 0.2)
                volume_success_prob = max(0.0, min(1.0, volume_success_prob))
                
                if volume_success_prob > 0.8:
                    volume_status = 1.0
                    exit_code = 0
                elif volume_success_prob > 0.5:
                    volume_status = 0.5
                    exit_code = random.choice([0, 24])  # 24 = partial transfer
                else:
                    volume_status = 0.0
                    exit_code = random.choice([1, 2, 10, 11, 12])  # Various error codes
                
                volume_rsync_stats = generate_rsync_stats()
                
                # Write volume status
                point = Point("backup_volume_status") \
                    .tag("host", host_name) \
                    .tag("path", volume_path) \
                    .field("status_numeric", volume_status) \
                    .field("exit_code", exit_code) \
                    .field("bytes_sent", volume_rsync_stats['bytes_sent']) \
                    .field("bytes_received", volume_rsync_stats['bytes_received']) \
                    .field("transfer_rate", volume_rsync_stats['transfer_rate']) \
                    .field("total_size", volume_rsync_stats['total_size']) \
                    .field("speedup", volume_rsync_stats['speedup']) \
                    .time(timestamp)
                
                write_api.write(bucket=influx_config['influxdb']['bucket'], record=point)
    
    # Generate overall backup status (latest timestamp only)
    latest_timestamp = timestamps[-1]
    
    # Overall status based on host statuses
    overall_success_rate = random.uniform(0.8, 0.95)
    if overall_success_rate > 0.9:
        overall_status = 1.0
    elif overall_success_rate > 0.7:
        overall_status = 0.5
    else:
        overall_status = 0.0
    
    # Write overall backup status
    point = Point("backup_status") \
        .field("status_numeric", overall_status) \
        .field("duration_seconds", total_duration // total_hosts) \
        .field("error_count", total_errors) \
        .field("total_size_bytes", total_size) \
        .field("scan_progress", random.uniform(0.95, 1.0)) \
        .time(latest_timestamp)
    
    write_api.write(bucket=influx_config['influxdb']['bucket'], record=point)
    
    print(f"✅ Generated test data:")
    print(f"   - {total_hosts} hosts")
    print(f"   - {total_volumes} total volumes")
    print(f"   - {len(timestamps)} time points")
    print(f"   - Overall status: {overall_status}")
    print(f"   - Total size: {total_size / (1024**3):.2f} GB")
    
    client.close()

def main():
    parser = argparse.ArgumentParser(description="Generate test data for backup testing")
    parser.add_argument("--client-id", type=int, help="Client ID for filesystem data generation")
    parser.add_argument("--data-size", choices=["small", "medium", "large"], default="medium",
                       help="Size of test data to generate")
    parser.add_argument("--metrics", action="store_true", help="Generate InfluxDB metrics data")
    
    args = parser.parse_args()
    
    if args.client_id:
        print(f"Generating filesystem test data for client {args.client_id}")
        print("=" * 50)
        generate_filesystem_data(args.client_id, args.data_size)
        print("✅ Filesystem data generation complete!")
        return
        
    if args.metrics:
        if not INFLUX_AVAILABLE:
            print("Error: InfluxDB client not available for metrics generation")
            sys.exit(1)
            
        print("Backup Metrics Test Data Generator")
        print("=" * 40)
        
        # Load configuration
        backup_config, influx_config = load_config()
        if not backup_config or not influx_config:
            print("Error: Could not load configuration files")
            sys.exit(1)
        
        print(f"Loaded backup config: {len(backup_config['hosts'])} hosts")
        print(f"InfluxDB target: {influx_config['influxdb']['url']}")
        print(f"Bucket: {influx_config['influxdb']['bucket']}")
        print()
        
        # Generate test data
        generate_test_data(backup_config, influx_config)
        
        print("\n✅ Test data generation complete!")
        print("You can now test your Grafana dashboard with this sample data.")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
