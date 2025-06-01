#!/usr/bin/env python3
"""
Enhanced Backup System Installer

This installer sets up the complete backup system including:
- InfluxDB and Grafana installation and configuration
- Backup script installation and systemd service setup
- Configuration file generation
- Firewall configuration
- BTRFS snapshot setup
"""

import os
import sys
import subprocess
import json
import shutil
import socket
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import platform
import getpass

# Try to import optional dependencies
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    PURPLE = '\033[0;35m'
    NC = '\033[0m'  # No Color

class BackupSystemInstaller:
    def __init__(self):
        self.script_dir = Path(__file__).parent.absolute()
        self.is_root = os.geteuid() == 0
        self.distro_info = self._detect_distribution()
        self.package_manager = self._detect_package_manager()
        self.firewall_manager = self._detect_firewall()
        self.config = {}
        self.influxdb_config = {}
        
    def print_header(self, text: str):
        print(f"{Colors.CYAN}=== {text} ==={Colors.NC}")
    
    def print_success(self, text: str):
        print(f"{Colors.GREEN}✓{Colors.NC} {text}")
    
    def print_error(self, text: str):
        print(f"{Colors.RED}✗{Colors.NC} {text}")
    
    def print_warning(self, text: str):
        print(f"{Colors.YELLOW}⚠{Colors.NC} {text}")
    
    def print_info(self, text: str):
        print(f"{Colors.BLUE}ℹ{Colors.NC} {text}")
    
    def ask_yes_no(self, question: str, default: bool = True) -> bool:
        """Ask a yes/no question with a default answer"""
        default_str = "Y/n" if default else "y/N"
        response = input(f"{question} ({default_str}): ").strip().lower()
        
        if not response:
            return default
        return response in ['y', 'yes', 'true', '1']
    
    def ask_input(self, question: str, default: str = "") -> str:
        """Ask for text input with optional default"""
        if default:
            response = input(f"{question} [{default}]: ").strip()
            return response if response else default
        else:
            while True:
                response = input(f"{question}: ").strip()
                if response:
                    return response
                print("This field is required.")
    
    def _detect_distribution(self) -> Dict[str, str]:
        """Detect Linux distribution"""
        try:
            with open('/etc/os-release', 'r') as f:
                lines = f.readlines()
            
            info = {}
            for line in lines:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    info[key] = value.strip('"')
            
            return {
                'id': info.get('ID', 'unknown'),
                'id_like': info.get('ID_LIKE', ''),
                'name': info.get('NAME', 'Unknown'),
                'version': info.get('VERSION_ID', 'unknown')
            }
        except Exception:
            return {'id': 'unknown', 'id_like': '', 'name': 'Unknown', 'version': 'unknown'}
    
    def _detect_package_manager(self) -> str:
        """Detect package manager"""
        managers = {
            'apt': ['debian', 'ubuntu'],
            'dnf': ['fedora', 'centos', 'rhel'],
            'zypper': ['opensuse', 'suse'],
            'pacman': ['arch'],
            'yum': ['centos', 'rhel']
        }
        
        distro_id = self.distro_info['id'].lower()
        distro_like = self.distro_info['id_like'].lower()
        
        for manager, distros in managers.items():
            if distro_id in distros or any(d in distro_like for d in distros):
                if shutil.which(manager):
                    return manager
        
        # Fallback detection
        for manager in ['apt', 'dnf', 'zypper', 'pacman', 'yum']:
            if shutil.which(manager):
                return manager
        
        return 'unknown'
    
    def _detect_firewall(self) -> str:
        """Detect firewall management system"""
        if shutil.which('ufw'):
            return 'ufw'
        elif shutil.which('firewall-cmd'):
            return 'firewalld'
        elif shutil.which('iptables'):
            return 'iptables'
        else:
            return 'none'
    
    def run_command(self, cmd: List[str], check: bool = True, capture_output: bool = False) -> subprocess.CompletedProcess:
        """Run a command with proper error handling"""
        try:
            if capture_output:
                result = subprocess.run(cmd, check=check, capture_output=True, text=True)
            else:
                result = subprocess.run(cmd, check=check)
            return result
        except subprocess.CalledProcessError as e:
            if check:
                self.print_error(f"Command failed: {' '.join(cmd)}")
                if capture_output and e.stderr:
                    self.print_error(f"Error: {e.stderr}")
                raise
            return e
    
    def check_service_running(self, service_name: str) -> bool:
        """Check if a systemd service is running"""
        try:
            result = self.run_command(['systemctl', 'is-active', service_name], check=False, capture_output=True)
            return result.returncode == 0 and result.stdout.strip() == 'active'
        except:
            return False
    
    def check_port_open(self, host: str, port: int) -> bool:
        """Check if a port is open"""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(3)
                result = sock.connect_ex((host, port))
                return result == 0
        except:
            return False
    
    def install_packages(self, packages: List[str]) -> bool:
        """Install packages using the detected package manager"""
        if not self.is_root:
            self.print_error("Root privileges required for package installation")
            return False
        
        cmd_map = {
            'apt': ['apt', 'update', '&&', 'apt', 'install', '-y'] + packages,
            'dnf': ['dnf', 'install', '-y'] + packages,
            'zypper': ['zypper', 'install', '-y'] + packages,
            'pacman': ['pacman', '-S', '--noconfirm'] + packages,
            'yum': ['yum', 'install', '-y'] + packages
        }
        
        if self.package_manager == 'apt':
            # Update package list first for apt
            self.run_command(['apt', 'update'])
            cmd = ['apt', 'install', '-y'] + packages
        else:
            cmd = cmd_map.get(self.package_manager)
        
        if not cmd:
            self.print_error(f"Unsupported package manager: {self.package_manager}")
            return False
        
        try:
            self.run_command(cmd)
            return True
        except subprocess.CalledProcessError:
            return False
    
    def configure_firewall(self, ports: List[int], services: List[str] = None) -> bool:
        """Configure firewall to allow specified ports and services"""
        if not self.is_root:
            self.print_warning("Root privileges required for firewall configuration")
            return False
        
        if self.firewall_manager == 'ufw':
            try:
                for port in ports:
                    self.run_command(['ufw', 'allow', str(port)])
                if services:
                    for service in services:
                        self.run_command(['ufw', 'allow', service])
                return True
            except subprocess.CalledProcessError:
                return False
        
        elif self.firewall_manager == 'firewalld':
            try:
                for port in ports:
                    self.run_command(['firewall-cmd', '--permanent', '--add-port', f'{port}/tcp'])
                if services:
                    for service in services:
                        self.run_command(['firewall-cmd', '--permanent', '--add-service', service])
                self.run_command(['firewall-cmd', '--reload'])
                return True
            except subprocess.CalledProcessError:
                return False
        
        elif self.firewall_manager == 'iptables':
            try:
                for port in ports:
                    self.run_command(['iptables', '-A', 'INPUT', '-p', 'tcp', '--dport', str(port), '-j', 'ACCEPT'])
                # Try to save iptables rules
                if shutil.which('iptables-save'):
                    self.run_command(['iptables-save'], check=False)
                return True
            except subprocess.CalledProcessError:
                return False
        
        else:
            self.print_warning("No supported firewall manager found")
            return False
    
    def check_existing_services(self) -> Dict[str, bool]:
        """Check if InfluxDB and Grafana are already installed and running"""
        services = {
            'influxdb': False,
            'grafana': False,
            'influxdb_port': False,
            'grafana_port': False
        }
        
        # Check services
        services['influxdb'] = self.check_service_running('influxdb')
        services['grafana'] = self.check_service_running('grafana-server')
        
        # Check ports
        services['influxdb_port'] = self.check_port_open('localhost', 8086)
        services['grafana_port'] = self.check_port_open('localhost', 3000)
        
        return services
    
    def install_influxdb(self) -> bool:
        """Install InfluxDB based on distribution"""
        self.print_header("Installing InfluxDB")
        
        if self.package_manager == 'apt':
            # Ubuntu/Debian
            try:
                # Add InfluxDB repository
                self.run_command(['wget', '-qO-', 'https://repos.influxdata.com/influxdata-archive_compat.key'])
                self.run_command(['bash', '-c', 'echo "deb https://repos.influxdata.com/debian stable main" | tee /etc/apt/sources.list.d/influxdb.list'])
                self.run_command(['apt', 'update'])
                
                # Ask for InfluxDB version
                if self.ask_yes_no("Install InfluxDB 2.x (recommended)?", True):
                    packages = ['influxdb2']
                else:
                    packages = ['influxdb']
                
                return self.install_packages(packages)
            except subprocess.CalledProcessError:
                self.print_error("Failed to install InfluxDB via repository")
                return False
        
        elif self.package_manager in ['dnf', 'yum']:
            # Fedora/RHEL/CentOS
            try:
                # Add repository - fix the escape sequence warning
                repo_content = """[influxdb]
name = InfluxDB Repository - RHEL
baseurl = https://repos.influxdata.com/rhel/$releasever/$basearch/stable/
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
"""
                with open('/etc/yum.repos.d/influxdb.repo', 'w') as f:
                    f.write(repo_content)
                
                if self.ask_yes_no("Install InfluxDB 2.x (recommended)?", True):
                    packages = ['influxdb2']
                else:
                    packages = ['influxdb']
                
                return self.install_packages(packages)
            except Exception:
                self.print_error("Failed to install InfluxDB via repository")
                return False
        
        elif self.package_manager == 'zypper':
            # openSUSE
            try:
                self.run_command(['zypper', 'addrepo', '-f', 'https://repos.influxdata.com/opensuse/stable/', 'influxdb'])
                if self.ask_yes_no("Install InfluxDB 2.x (recommended)?", True):
                    packages = ['influxdb2']
                else:
                    packages = ['influxdb']
                return self.install_packages(packages)
            except subprocess.CalledProcessError:
                return False
        
        else:
            self.print_error(f"InfluxDB installation not supported for {self.package_manager}")
            return False
    
    def install_grafana(self) -> bool:
        """Install Grafana based on distribution"""
        self.print_header("Installing Grafana")
        
        if self.package_manager == 'apt':
            try:
                # Add Grafana repository
                self.run_command(['wget', '-q', '-O', '-', 'https://packages.grafana.com/gpg.key'], capture_output=True)
                self.run_command(['bash', '-c', 'echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list'])
                self.run_command(['apt', 'update'])
                return self.install_packages(['grafana'])
            except subprocess.CalledProcessError:
                return False
        
        elif self.package_manager in ['dnf', 'yum']:
            try:
                repo_content = """[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
"""
                with open('/etc/yum.repos.d/grafana.repo', 'w') as f:
                    f.write(repo_content)
                return self.install_packages(['grafana'])
            except Exception:
                return False
        
        elif self.package_manager == 'zypper':
            try:
                self.run_command(['zypper', 'addrepo', 'https://packages.grafana.com/oss/rpm', 'grafana'])
                return self.install_packages(['grafana'])
            except subprocess.CalledProcessError:
                return False
        
        else:
            self.print_error(f"Grafana installation not supported for {self.package_manager}")
            return False
    
    def setup_influxdb(self) -> Dict[str, str]:
        """Setup InfluxDB and return connection details"""
        self.print_header("Setting up InfluxDB")
        
        if not HAS_REQUESTS:
            self.print_error("requests library required for InfluxDB setup")
            self.print_info("Install with: pip3 install requests")
            return {}
        
        # Start InfluxDB service
        if self.is_root:
            self.run_command(['systemctl', 'enable', 'influxdb2'])
            self.run_command(['systemctl', 'start', 'influxdb2'])
        
        # Wait for InfluxDB to start
        import time
        for i in range(30):
            if self.check_port_open('localhost', 8086):
                break
            time.sleep(1)
        else:
            self.print_error("InfluxDB failed to start")
            return {}
        
        # Check if InfluxDB is already configured
        try:
            response = requests.get('http://localhost:8086/api/v2/setup', timeout=5)
            if response.status_code == 200:
                setup_data = response.json()
                if not setup_data.get('allowed', True):
                    self.print_info("InfluxDB is already configured")
                    # Ask for existing configuration
                    token = self.ask_input("Enter your InfluxDB token")
                    org = self.ask_input("Enter your organization name", "home")
                    bucket = self.ask_input("Enter your bucket name", "backup")
                    return {
                        'host': 'localhost',
                        'port': '8086',
                        'token': token,
                        'organization': org,
                        'bucket': bucket
                    }
        except requests.RequestException:
            pass
        
        # Initial setup for InfluxDB 2.x
        print("\nConfiguring InfluxDB 2.x:")
        username = self.ask_input("Enter admin username", "admin")
        password = getpass.getpass("Enter admin password: ")
        org = self.ask_input("Enter organization name", "home")
        bucket = self.ask_input("Enter bucket name", "backup")
        
        setup_data = {
            'username': username,
            'password': password,
            'org': org,
            'bucket': bucket,
            'retentionPeriodSeconds': 0  # Infinite retention
        }
        
        try:
            response = requests.post('http://localhost:8086/api/v2/setup', json=setup_data, timeout=10)
            if response.status_code == 201:
                result = response.json()
                self.print_success("InfluxDB setup completed")
                return {
                    'host': 'localhost',
                    'port': '8086',
                    'token': result['auth']['token'],
                    'organization': org,
                    'bucket': bucket
                }
            else:
                self.print_error(f"InfluxDB setup failed: {response.text}")
                return {}
        except requests.RequestException as e:
            self.print_error(f"Failed to configure InfluxDB: {e}")
            return {}
    
    def setup_grafana(self, influxdb_config: Dict[str, str]) -> bool:
        """Setup Grafana and configure InfluxDB data source"""
        self.print_header("Setting up Grafana")
        
        if self.is_root:
            self.run_command(['systemctl', 'enable', 'grafana-server'])
            self.run_command(['systemctl', 'start', 'grafana-server'])
        
        # Wait for Grafana to startthe test script should onl
        import time
        for i in range(30):
            if self.check_port_open('localhost', 3000):
                break
            time.sleep(1)
        else:
            self.print_error("Grafana failed to start")
            return False
        
        self.print_success("Grafana is running at http://localhost:3000")
        self.print_info("Default login: admin/admin (you'll be prompted to change it)")
        
        # Configure InfluxDB data source
        if influxdb_config:
            self.print_info("You can configure the InfluxDB data source in Grafana:")
            self.print_info(f"  URL: http://localhost:{influxdb_config['port']}")
            self.print_info(f"  Organization: {influxdb_config['organization']}")
            self.print_info(f"  Token: {influxdb_config['token']}")
            self.print_info(f"  Default Bucket: {influxdb_config['bucket']}")
        
        return True
    
    def check_btrfs(self, path: str) -> bool:
        """Check if a path is on a BTRFS filesystem"""
        try:
            result = self.run_command(['df', '-T', path], capture_output=True)
            return 'btrfs' in result.stdout
        except:
            return False
    
    def setup_backup_config(self) -> Dict:
        """Interactive setup of backup configuration"""
        self.print_header("Backup Configuration Setup")
        
        config = {
            'config': {
                'backup_base': '/share/backup/',
                'lock_file': '/tmp/backup.fil',
                'rsync_options': '-avz --delete --numeric-ids --stats --human-readable'
            },
            'hosts': {},
            'snapshots': {
                'volume': '/share',
                'schedules': []
            }
        }
        
        # Basic configuration
        backup_base = self.ask_input("Enter backup destination directory", "/share/backup/")
        config['config']['backup_base'] = backup_base
        
        # Check if backup directory is on BTRFS
        backup_dir = Path(backup_base).parent
        is_btrfs = self.check_btrfs(str(backup_dir))
        
        if is_btrfs:
            self.print_success(f"Backup directory is on BTRFS filesystem")
            if self.ask_yes_no("Configure BTRFS snapshots?", True):
                self.setup_snapshots_config(config)
            else:
                # Remove snapshots section if user doesn't want them
                del config['snapshots']
        else:
            self.print_warning(f"Backup directory is not on BTRFS filesystem")
            if self.ask_yes_no("Continue without snapshots?", True):
                del config['snapshots']
            else:
                self.print_error("BTRFS filesystem required for snapshots")
                return {}
        
        # Host configuration
        self.setup_hosts_config(config)
        
        return config
    
    def setup_snapshots_config(self, config: Dict):
        """Setup BTRFS snapshot configuration"""
        self.print_info("Configuring BTRFS snapshots...")
        
        snapshot_volume = self.ask_input("Enter snapshot volume path", "/share")
        config['snapshots']['volume'] = snapshot_volume
        
        # Default snapshot schedules
        default_schedules = [
            {'type': 'hourly', 'count': 6, 'interval': 14400},  # 4 hours
            {'type': 'daily', 'count': 7, 'interval': 86400},   # 1 day
            {'type': 'weekly', 'count': 4, 'interval': 604800}, # 1 week
            {'type': 'monthly', 'count': 12, 'interval': 2592000} # 30 days
        ]
        
        self.print_info("Default snapshot schedule:")
        for schedule in default_schedules:
            hours = schedule['interval'] // 3600
            self.print_info(f"  {schedule['type']}: Keep {schedule['count']} snapshots, taken every {hours} hours")
        
        if self.ask_yes_no("Use default snapshot schedule?", True):
            config['snapshots']['schedules'] = default_schedules
        else:
            config['snapshots']['schedules'] = []
            while self.ask_yes_no("Add custom snapshot schedule?", False):
                schedule_type = self.ask_input("Schedule type (hourly/daily/weekly/monthly)")
                count = int(self.ask_input("Number of snapshots to keep", "7"))
                hours = int(self.ask_input("Interval in hours", "24"))
                interval = hours * 3600
                
                config['snapshots']['schedules'].append({
                    'type': schedule_type,
                    'count': count,
                    'interval': interval
                })
    
    def setup_hosts_config(self, config: Dict):
        """Setup host configuration"""
        self.print_info("Configuring backup hosts...")
        
        while self.ask_yes_no("Add a backup host?", True):
            hostname = self.ask_input("Enter hostname/identifier")
            
            host_config = {
                'paths': []
            }
            
            # SSH configuration
            if self.ask_yes_no("Is this a remote host (requires SSH)?", True):
                ssh_user = self.ask_input("SSH username", "backup")
                target_hostname = self.ask_input("Target hostname/IP", hostname)
                ssh_key = self.ask_input("SSH key path", "/root/.ssh/id_ed25519")
                
                host_config['ssh_user'] = ssh_user
                host_config['hostname'] = target_hostname
                host_config['ssh_key'] = ssh_key
                
                if self.ask_yes_no("Ignore ping test for this host?", False):
                    host_config['ignore_ping'] = True
            
            # Backup paths
            while self.ask_yes_no(f"Add backup path for {hostname}?", True):
                path = self.ask_input("Enter path to backup", "/etc")
                dest_subdir = self.ask_input("Destination subdirectory (optional)", "")
                
                path_config = {'path': path}
                if dest_subdir:
                    path_config['dest_subdir'] = dest_subdir
                
                if self.ask_yes_no("Add exclude file for this path?", False):
                    exclude_file = self.ask_input("Exclude file path")
                    path_config['exclude_file'] = exclude_file
                
                host_config['paths'].append(path_config)
            
            config['hosts'][hostname] = host_config
        
        if not config['hosts']:
            self.print_error("At least one host must be configured")
            return False
        
        return True
    
    def install_backup_scripts(self) -> bool:
        """Install backup scripts to /usr/local/bin"""
        self.print_header("Installing Backup Scripts")
        
        if not self.is_root:
            self.print_error("Root privileges required to install scripts")
            return False
        
        scripts = [
            ('backup-new.sh', '/usr/local/bin/backup-new'),
            ('backup-metrics', '/usr/local/bin/backup-metrics'),
            ('job_pool.sh', '/usr/local/bin/job_pool.sh')
        ]
        
        for script_name, dest_path in scripts:
            source_path = self.script_dir / script_name
            
            if not source_path.exists():
                # Try to download job_pool.sh if missing
                if script_name == 'job_pool.sh':
                    try:
                        import urllib.request
                        url = 'https://raw.githubusercontent.com/vincetse/shellutils/master/job_pool.sh'
                        urllib.request.urlretrieve(url, str(source_path))
                        self.print_success(f"Downloaded {script_name}")
                    except Exception as e:
                        self.print_error(f"Failed to download {script_name}: {e}")
                        continue
                else:
                    self.print_error(f"Source script not found: {source_path}")
                    return False
            
            try:
                shutil.copy2(str(source_path), dest_path)
                os.chmod(dest_path, 0o755)
                self.print_success(f"Installed {script_name} to {dest_path}")
            except Exception as e:
                self.print_error(f"Failed to install {script_name}: {e}")
                return False
        
        return True
    
    def create_systemd_service(self) -> bool:
        """Create systemd service and timer files"""
        self.print_header("Creating Systemd Service")
        
        if not self.is_root:the test script should onl services")
            return False
        
        # Service file
        service_content = """[Unit]
Description=Enhanced Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-new --backup
User=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
"""
        
        # Timer file
        frequency = self.ask_input("Backup frequency (examples: hourly, daily, *-*-* 00/2:00:00)", "*-*-* 00/2:00:00")
        
        timer_content = f"""[Unit]
Description=Timer for Enhanced Backup Service

[Timer]
OnCalendar={frequency}
Persistent=yes
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
"""
        
        try:
            # Write service file
            with open('/etc/systemd/system/backup.service', 'w') as f:
                f.write(service_content)
            
            # Write timer file
            with open('/etc/systemd/system/backup.timer', 'w') as f:
                f.write(timer_content)
            
            # Reload systemd and enable timer
            self.run_command(['systemctl', 'daemon-reload'])
            self.run_command(['systemctl', 'enable', 'backup.timer'])
            
            if self.ask_yes_no("Start backup timer now?", True):
                self.run_command(['systemctl', 'start', 'backup.timer'])
            
            self.print_success("Systemd service and timer created")
            return True
            
        except Exception as e:
            self.print_error(f"Failed to create systemd service: {e}")
            return False
    
    def save_configurations(self, backup_config: Dict, influxdb_config: Dict) -> bool:
        """Save configuration files"""
        self.print_header("Saving Configuration Files")
        
        if not HAS_YAML:
            self.print_error("PyYAML library required to save configurations")
            self.print_info("Install with: pip3 install pyyaml")
            return False
        
        # Create backup config directory
        config_dir = Path('/etc/backup')
        config_dir.mkdir(parents=True, exist_ok=True)
        
        try:
            # Save backup configuration
            with open('/etc/backup/backup.yaml', 'w') as f:
                yaml.dump(backup_config, f, default_flow_style=False, indent=2)
            self.print_success("Saved backup configuration to /etc/backup/backup.yaml")
            
            # Save InfluxDB configuration
            influx_config = {'influxdb': influxdb_config}
            with open('/etc/backup/influxdb-config.yaml', 'w') as f:
                yaml.dump(influx_config, f, default_flow_style=False, indent=2)
            self.print_success("Saved InfluxDB configuration to /etc/backup/influxdb-config.yaml")
            
            # Copy dashboard if it exists
            dashboard_source = self.script_dir / 'dashboard-cleaned-up.json'
            if dashboard_source.exists():
                shutil.copy2(str(dashboard_source), '/etc/backup/grafana-dashboard.json')
                self.print_success("Copied Grafana dashboard to /etc/backup/grafana-dashboard.json")
            
            return True
            
        except Exception as e:
            self.print_error(f"Failed to save configurations: {e}")
            return False
    
    def install_dependencies(self) -> bool:
        """Install system dependencies"""
        # Declare globals at the very beginning
        global yaml, HAS_YAML, requests, HAS_REQUESTS
        
        self.print_header("Installing System Dependencies")
        
        # Required packages
        packages = ['python3', 'python3-pip', 'rsync', 'btrfs-progs']
        
        # Distribution-specific packages
        if self.package_manager == 'apt':
            packages.extend(['python3-yaml', 'python3-requests'])
        elif self.package_manager in ['dnf', 'yum']:
            packages.extend(['python3-pyyaml', 'python3-requests'])
        elif self.package_manager == 'zypper':
            packages.extend(['python3-PyYAML', 'python3-requests'])
        
        # Install yq if available
        if self.package_manager == 'apt':
            packages.append('yq')
        
        try:
            if self.is_root:
                self.install_packages(packages)
                self.print_success("System dependencies installed")
            else:
                self.print_warning("Root privileges required for system package installation")
                self.print_info("You may need to run: sudo apt install python3-yaml python3-requests")
            
            # Install Python packages via pip if system packages aren't available
            if not HAS_YAML or not HAS_REQUESTS:
                missing_packages = []
                if not HAS_YAML:
                    missing_packages.append('pyyaml')
                if not HAS_REQUESTS:
                    missing_packages.append('requests')
                
                self.print_info(f"Installing missing Python packages: {', '.join(missing_packages)}")
                try:
                    self.run_command(['pip3', 'install'] + missing_packages)
                    self.print_success("Python dependencies installed via pip")
                    
                    # Now reload the modules safely
                    if not HAS_YAML:
                        import yaml
                        HAS_YAML = True
                    if not HAS_REQUESTS:
                        import requests
                        HAS_REQUESTS = True
                        
                except subprocess.CalledProcessError:
                    self.print_error("Failed to install Python dependencies via pip")
                    self.print_info("Please manually install: pip3 install pyyaml requests")
                    return False
            
            return True
        except subprocess.CalledProcessError:
            self.print_error("Failed to install some dependencies")
            return False
    
    def run_installer(self):
        """Main installer workflow"""
        self.print_header("Enhanced Backup System Installer")
        self.print_info(f"Detected distribution: {self.distro_info['name']}")
        self.print_info(f"Package manager: {self.package_manager}")
        self.print_info(f"Firewall: {self.firewall_manager}")
        
        # Check for required Python modules early - try importing again after potential installation
        global yaml, HAS_YAML, requests, HAS_REQUESTS
        
        # Re-check imports after potential installation
        try:
            import yaml
            HAS_YAML = True
        except ImportError:
            pass
        
        try:
            import requests
            HAS_REQUESTS = True
        except ImportError:
            pass
        
        if not HAS_YAML or not HAS_REQUESTS:
            missing = []
            if not HAS_YAML:
                missing.append("PyYAML")
            if not HAS_REQUESTS:
                missing.append("requests")
            
            self.print_warning(f"Missing Python dependencies: {', '.join(missing)}")
            if self.ask_yes_no("Install missing dependencies now?", True):
                if not self.install_dependencies():
                    self.print_error("Failed to install dependencies. Please install manually:")
                    self.print_info("pip3 install pyyaml requests")
                    sys.exit(1)
            else:
                self.print_error("Required dependencies missing. Cannot continue.")
                sys.exit(1)
        else:
            self.print_success("All required Python dependencies are available")
        
        if not self.is_root:
            self.print_warning("Some installation steps require root privileges")
            if not self.ask_yes_no("Continue with limited installation?", False):
                sys.exit(1)
        
        # Check existing services
        existing = self.check_existing_services()
        
        influxdb_config = {}
        grafana_installed = False
        
        # InfluxDB setup
        if existing['influxdb'] or existing['influxdb_port']:
            self.print_info("InfluxDB appears to be already running")
            if self.ask_yes_no("Configure existing InfluxDB instance?", True):
                influxdb_config = {
                    'host': 'localhost',
                    'port': '8086',
                    'token': self.ask_input("Enter InfluxDB token"),
                    'organization': self.ask_input("Enter organization", "home"),
                    'bucket': self.ask_input("Enter bucket name", "backup")
                }
        else:
            if self.ask_yes_no("Install and configure InfluxDB?", True):
                if self.install_dependencies() and self.install_influxdb():
                    influxdb_config = self.setup_influxdb()
                    if influxdb_config and self.is_root:
                        self.configure_firewall([8086])
        
        # Grafana setup
        if existing['grafana'] or existing['grafana_port']:
            self.print_info("Grafana appears to be already running")
            grafana_installed = True
        else:
            if self.ask_yes_no("Install and configure Grafana?", True):
                if self.install_grafana():
                    grafana_installed = self.setup_grafana(influxdb_config)
                    if grafana_installed and self.is_root:
                        self.configure_firewall([3000])
        
        # Backup configuration
        backup_config = self.setup_backup_config()
        if not backup_config:
            self.print_error("Backup configuration failed")
            sys.exit(1)
        
        # Install scripts and create service
        if self.is_root:
            self.install_backup_scripts()
            self.create_systemd_service()
        
        # Save configurations
        self.save_configurations(backup_config, influxdb_config)
        
        # Final summary
        self.print_header("Installation Complete!")
        
        if influxdb_config:
            self.print_success("InfluxDB configured")
            self.print_info(f"  URL: http://localhost:{influxdb_config['port']}")
            self.print_info(f"  Organization: {influxdb_config['organization']}")
            self.print_info(f"  Bucket: {influxdb_config['bucket']}")
        
        if grafana_installed:
            self.print_success("Grafana configured")
            self.print_info("  URL: http://localhost:3000")
            self.print_info("  Default login: admin/admin")
            
            if influxdb_config:
                self.print_info("  Import dashboard from: /etc/backup/grafana-dashboard.json")
        
        self.print_success("Backup system configured")
        self.print_info("  Configuration: /etc/backup/backup.yaml")
        self.print_info("  Scripts installed in: /usr/local/bin/")
        
        if self.is_root:
            self.print_info("  Systemd timer: backup.timer")
            self.print_info("  Check status: systemctl status backup.timer")
        
        self.print_info("\nNext steps:")
        self.print_info("1. Verify host connectivity: backup-new --verify-hosts")
        self.print_info("2. Test backup: backup-new --dry-run")
        self.print_info("3. Send test metrics: backup-metrics --test-influxdb")
        
        if grafana_installed:
            self.print_info("4. Import Grafana dashboard and configure data source")

def main():
    installer = BackupSystemInstaller()
    
    try:
        installer.run_installer()
    except KeyboardInterrupt:
        installer.print_warning("\nInstallation cancelled by user")
        sys.exit(1)
    except Exception as e:
        installer.print_error(f"Installation failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()