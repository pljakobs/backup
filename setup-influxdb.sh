#!/bin/bash
# InfluxDB + Grafana Setup Script for Backup Monitoring

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

print_header "Backup Monitoring Setup - InfluxDB + Grafana"

# Install Python dependencies
print_info "Installing Python dependencies..."
if command -v pip3 &> /dev/null; then
    pip3 install --user pyyaml requests
    print_success "Python dependencies installed"
else
    print_error "pip3 not found. Please install python3-pip package"
    exit 1
fi

# Create directories
print_info "Creating monitoring directories..."
mkdir -p ~/monitoring/{influxdb,grafana}
mkdir -p ~/monitoring/influxdb/{data,config}
mkdir -p ~/monitoring/grafana/{data,dashboards,provisioning/{datasources,dashboards}}

print_success "Directories created"

# Create InfluxDB configuration
print_info "Creating InfluxDB configuration..."
cat > ~/monitoring/influxdb/config/influxdb.conf << 'EOF'
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"

[coordinator]

[retention]

[shard-precreation]

[monitor]

[subscriber]

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = false
  log-enabled = true
  write-tracing = false
  pprof-enabled = true
  debug-pprof-enabled = false
  https-enabled = false

[logging]
  format = "auto"
  level = "info"

[[graphite]]

[[collectd]]

[[opentsdb]]

[[udp]]

[continuous_queries]
  log-enabled = true
  enabled = true
EOF

# Create Grafana datasource configuration
print_info "Creating Grafana datasource configuration..."
cat > ~/monitoring/grafana/provisioning/datasources/influxdb.yml << 'EOF'
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    database: backup_metrics
    isDefault: true
    editable: true
    jsonData:
      timeInterval: "10s"
    secureJsonData: {}
EOF

# Create Grafana dashboard provisioning
print_info "Creating Grafana dashboard provisioning..."
cat > ~/monitoring/grafana/provisioning/dashboards/backup-dashboards.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'backup-dashboards'
    orgId: 1
    folder: 'Backup Monitoring'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Create backup monitoring dashboard
print_info "Creating Grafana backup dashboard..."
cat > ~/monitoring/grafana/dashboards/backup-monitoring.json << 'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "datasource": "InfluxDB",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [
            {
              "options": {
                "0": {
                  "color": "red",
                  "index": 0,
                  "text": "Failed"
                },
                "1": {
                  "color": "green",
                  "index": 1,
                  "text": "Success"
                }
              },
              "type": "value"
            }
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "red",
                "value": null
              },
              {
                "color": "green",
                "value": 1
              }
            ]
          },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "colorMode": "background",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      },
      "pluginVersion": "8.0.0",
      "targets": [
        {
          "query": "SELECT last(\"last_run_success\") FROM \"backup_status\" WHERE $timeFilter",
          "rawQuery": true,
          "refId": "A"
        }
      ],
      "title": "Last Backup Status",
      "type": "stat"
    },
    {
      "datasource": "InfluxDB",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "vis": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "s"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "query": "SELECT mean(\"duration_seconds\") FROM \"backup_status\" WHERE $timeFilter GROUP BY time(1h) fill(null)",
          "rawQuery": true,
          "refId": "A"
        }
      ],
      "title": "Backup Duration",
      "type": "timeseries"
    },
    {
      "datasource": "InfluxDB",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "vis": false
            }
          },
          "mappings": [
            {
              "options": {
                "0": {
                  "color": "red",
                  "index": 0,
                  "text": "Failed"
                },
                "1": {
                  "color": "green",
                  "index": 1,
                  "text": "Success"
                }
              },
              "type": "value"
            }
          ]
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 8
      },
      "id": 3,
      "options": {
        "displayLabels": [
          "name"
        ],
        "legend": {
          "displayMode": "table",
          "placement": "right",
          "values": [
            "value"
          ]
        },
        "pieType": "pie",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "query": "SELECT last(\"last_success\") FROM \"backup_host\" WHERE $timeFilter GROUP BY \"host\"",
          "rawQuery": true,
          "refId": "A"
        }
      ],
      "title": "Host Backup Status",
      "type": "piechart"
    },
    {
      "datasource": "InfluxDB",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "vis": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "bytes"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 16
      },
      "id": 4,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "query": "SELECT last(\"size_bytes\") FROM \"backup_host\" WHERE $timeFilter GROUP BY \"host\"",
          "rawQuery": true,
          "refId": "A"
        }
      ],
      "title": "Backup Size by Host",
      "type": "timeseries"
    },
    {
      "datasource": "InfluxDB",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "vis": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 16
      },
      "id": 5,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "targets": [
        {
          "query": "SELECT sum(\"error_count\") FROM \"backup_status\" WHERE $timeFilter GROUP BY time(1h) fill(null)",
          "rawQuery": true,
          "refId": "A"
        }
      ],
      "title": "Backup Errors Over Time",
      "type": "timeseries"
    }
  ],
  "schemaVersion": 27,
  "style": "dark",
  "tags": [
    "backup",
    "monitoring"
  ],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Backup Monitoring Dashboard",
  "uid": "backup-monitoring",
  "version": 1
}
EOF

# Create Docker Compose file
print_info "Creating Docker Compose configuration..."
cat > ~/monitoring/docker-compose.yml << 'EOF'
version: '3.8'

services:
  influxdb:
    image: influxdb:1.8-alpine
    container_name: backup-influxdb
    restart: unless-stopped
    ports:
      - "8086:8086"
    volumes:
      - ./influxdb/data:/var/lib/influxdb
      - ./influxdb/config/influxdb.conf:/etc/influxdb/influxdb.conf:ro
    environment:
      - INFLUXDB_DB=backup_metrics
      - INFLUXDB_ADMIN_USER=admin
      - INFLUXDB_ADMIN_PASSWORD=admin123
      - INFLUXDB_USER=backup
      - INFLUXDB_USER_PASSWORD=backup123
    command: influxd -config /etc/influxdb/influxdb.conf

  grafana:
    image: grafana/grafana:latest
    container_name: backup-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    depends_on:
      - influxdb

networks:
  default:
    name: backup-monitoring
EOF

# Create systemd service for metrics collection
print_info "Creating systemd service for metrics collection..."
sudo tee /etc/systemd/system/backup-metrics-influx.service > /dev/null << EOF
[Unit]
Description=Backup Metrics Collector (InfluxDB)
After=network.target

[Service]
Type=oneshot
User=$(whoami)
WorkingDirectory=/home/pjakobs/devel/backup
ExecStart=/usr/bin/python3 /home/pjakobs/devel/backup/backup-metrics.py --send-influxdb
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer for regular metrics collection
sudo tee /etc/systemd/system/backup-metrics-influx.timer > /dev/null << EOF
[Unit]
Description=Run backup metrics collection every 5 minutes (InfluxDB)
Requires=backup-metrics-influx.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

print_success "Systemd service and timer created"

# Create helper scripts
print_info "Creating helper scripts..."

# Script to start monitoring stack
cat > ~/monitoring/start-monitoring.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Starting backup monitoring stack..."
docker-compose up -d
echo "Monitoring stack started!"
echo "InfluxDB: http://localhost:8086"
echo "Grafana: http://localhost:3000 (admin/admin123)"
echo ""
echo "Waiting for services to be ready..."
sleep 10
echo "Creating database..."
curl -X POST "http://localhost:8086/query" --data-urlencode "q=CREATE DATABASE backup_metrics" || true
echo "Database created (or already exists)"
EOF
chmod +x ~/monitoring/start-monitoring.sh

# Script to stop monitoring stack
cat > ~/monitoring/stop-monitoring.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Stopping backup monitoring stack..."
docker-compose down
echo "Monitoring stack stopped!"
EOF
chmod +x ~/monitoring/stop-monitoring.sh

# Script to view logs
cat > ~/monitoring/view-logs.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -z "$1" ]; then
    echo "Usage: $0 [influxdb|grafana]"
    exit 1
fi
docker-compose logs -f "$1"
EOF
chmod +x ~/monitoring/view-logs.sh

# Test metrics collection script
cat > ~/monitoring/test-metrics.sh << 'EOF'
#!/bin/bash
echo "Testing metrics collection..."
cd /home/pjakobs/devel/backup

echo "1. Testing JSON output:"
python3 backup-metrics.py --json

echo -e "\n2. Testing InfluxDB line protocol output:"
python3 backup-metrics.py --influxdb
if [ -f /tmp/backup_metrics.influxdb ]; then
    echo "Sample InfluxDB metrics:"
    head -5 /tmp/backup_metrics.influxdb
else
    echo "No InfluxDB metrics file found"
fi

echo -e "\n3. Testing direct InfluxDB send (requires running InfluxDB):"
python3 backup-metrics.py --send-influxdb
EOF
chmod +x ~/monitoring/test-metrics.sh

print_success "Helper scripts created"

# Reload systemd
sudo systemctl daemon-reload

print_header "Setup Complete!"

print_info "Next steps:"
echo "1. Start the monitoring stack:"
echo "   cd ~/monitoring && ./start-monitoring.sh"
echo ""
echo "2. Test metrics collection:"
echo "   cd ~/monitoring && ./test-metrics.sh"
echo ""
echo "3. Enable automatic metrics collection:"
echo "   sudo systemctl enable backup-metrics-influx.timer"
echo "   sudo systemctl start backup-metrics-influx.timer"
echo ""
echo "4. Access Grafana dashboard:"
echo "   URL: http://localhost:3000"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "5. View collected metrics:"
echo "   InfluxDB: http://localhost:8086"
echo "   Database: backup_metrics"
echo ""

print_warning "Make sure Docker and Docker Compose are installed!"
print_warning "Run 'docker --version' and 'docker-compose --version' to verify."

print_success "Backup monitoring setup complete!"
