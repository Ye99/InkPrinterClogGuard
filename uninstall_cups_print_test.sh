#!/bin/bash
# Uninstall script for CUPS-based Print Test Page service
# This script removes the systemd service and timer files

set -e

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

SERVICE_NAME="print_test_page_cups"

# Stop and disable the timer and service
echo "Stopping and disabling $SERVICE_NAME.timer..."
systemctl stop "$SERVICE_NAME.timer" 2>/dev/null || true
systemctl disable "$SERVICE_NAME.timer" 2>/dev/null || true

echo "Stopping $SERVICE_NAME.service (if running)..."
systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true

# Remove service and timer files
echo "Removing $SERVICE_NAME service and timer files..."
rm -f /etc/systemd/system/$SERVICE_NAME.service
rm -f /etc/systemd/system/$SERVICE_NAME.timer

# Reload systemd
systemctl daemon-reload

echo "Uninstallation complete." 