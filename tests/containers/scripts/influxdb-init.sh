#!/bin/bash
# InfluxDB initialization script

echo "Setting up backup metrics bucket and retention policies..."

# Wait for InfluxDB to be ready
sleep 30

# Create retention policy for backup metrics (keep data for 30 days)
influx bucket create \
    --name backup-metrics-detailed \
    --org backup-org \
    --retention 720h || true

echo "InfluxDB initialization complete"
