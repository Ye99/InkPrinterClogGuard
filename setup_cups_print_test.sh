#!/bin/bash
# Setup script for CUPS-based Print Test Page service
# This script installs the necessary systemd service and timer files

set -e

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check if CUPS is installed
if ! dpkg -l cups > /dev/null 2>&1; then
  echo "CUPS is not installed. Updating package lists..."
  apt update
  
  echo "Installing CUPS..."
  apt install -y cups
  
  # Make sure CUPS service is running
  systemctl enable cups
  systemctl start cups
  
  echo "CUPS has been installed and started."
else
  echo "CUPS is already installed."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="print_test_page_cups"
PRINT_SCRIPT="print_test_page_cups.sh"
PDF_PATH="$SCRIPT_DIR/default-testpage.pdf"

# Verify the PDF file exists
if [ ! -f "$PDF_PATH" ]; then
  echo "Error: default-testpage.pdf not found in $SCRIPT_DIR"
  echo "Please make sure the PDF file is in the same directory as this script."
  exit 1
fi

# Find EPSON ET printers from CUPS
echo "Searching for EPSON ET printers..."
declare -a EPSON_PRINTERS=()

# Get list of available printers
while read -r printer; do
  # Check if printer name starts with EPSON_ET_
  if [[ "$printer" == EPSON_ET_* ]]; then
    EPSON_PRINTERS+=("$printer")
    echo "Found EPSON ET printer: $printer"
  fi
done < <(lpstat -p | grep -oP '(?<=printer ).*' | cut -d ' ' -f1)

if [ ${#EPSON_PRINTERS[@]} -eq 0 ]; then
  echo "No EPSON ET printers found. Please add a printer in CUPS and try again."
  exit 1
fi

echo "Found ${#EPSON_PRINTERS[@]} EPSON ET printer(s)"

# Update the print script with all detected printers
echo "Updating print script with all detected printers..."
cat > "$SCRIPT_DIR/$PRINT_SCRIPT" << EOF
#!/bin/bash
# Print the CUPS test page on all EPSON ET printers
# lpstat -p to show available printers

# Path to our local PDF test page
PDF_PATH="$PDF_PATH"

# Print test page to all detected EPSON ET printers
EOF

# Add print commands for each printer
for printer in "${EPSON_PRINTERS[@]}"; do
  echo "echo \"Printing test page to $printer...\"" >> "$SCRIPT_DIR/$PRINT_SCRIPT"
  echo "lp -d \"$printer\" \"\$PDF_PATH\"" >> "$SCRIPT_DIR/$PRINT_SCRIPT"
  echo "" >> "$SCRIPT_DIR/$PRINT_SCRIPT"
done

chmod +x "$SCRIPT_DIR/$PRINT_SCRIPT"

# Install service and timer files to systemd directory
echo "Installing $SERVICE_NAME service and timer files..."

# Read the service file, update the path, and write to systemd directory
SERVICE_FILE="$SCRIPT_DIR/$SERVICE_NAME.service"
if [ -f "$SERVICE_FILE" ]; then
  # Update the ExecStart path in the service file
  sed "s|ExecStart=.*|ExecStart=/bin/bash $SCRIPT_DIR/$PRINT_SCRIPT|g" "$SERVICE_FILE" > "/etc/systemd/system/$SERVICE_NAME.service"
  echo "Service file installed with script path: $SCRIPT_DIR/$PRINT_SCRIPT"
else
  echo "Error: Service file not found at $SERVICE_FILE"
  exit 1
fi

# Copy the timer file
cp "$SCRIPT_DIR/$SERVICE_NAME.timer" /etc/systemd/system/

# Reload systemd to recognize new files
systemctl daemon-reload

# Enable and start the timer
echo "Enabling and starting $SERVICE_NAME.timer..."
systemctl enable "$SERVICE_NAME.timer"
systemctl start "$SERVICE_NAME.timer"

# Print a clear summary of the installation
echo
echo "========================================================"
echo "                 INSTALLATION SUMMARY                   "
echo "========================================================"
echo "Print test service has been set up successfully!"
echo
echo "TIMER SCHEDULE:"
# Read actual timer settings from the installed timer file
TIMER_FILE="/etc/systemd/system/$SERVICE_NAME.timer"
if [ -f "$TIMER_FILE" ]; then
  # Extract timer settings
  UNIT_ACTIVE_SEC=$(grep -oP 'OnUnitActiveSec=\K.*' "$TIMER_FILE" 2>/dev/null || echo "N/A")
  BOOT_SEC=$(grep -oP 'OnBootSec=\K.*' "$TIMER_FILE" 2>/dev/null || echo "N/A")
  CALENDAR=$(grep -oP 'OnCalendar=\K.*' "$TIMER_FILE" 2>/dev/null || echo "N/A")
  
  # Display actual timer settings
  [ "$UNIT_ACTIVE_SEC" != "N/A" ] && echo "  - Will run every: $UNIT_ACTIVE_SEC"
  [ "$BOOT_SEC" != "N/A" ] && echo "  - Will run after boot: $BOOT_SEC"
  [ "$CALENDAR" != "N/A" ] && echo "  - Will run on calendar: $CALENDAR"
  
  # Display other relevant timer settings
  PERSISTENT=$(grep -oP 'Persistent=\K.*' "$TIMER_FILE" 2>/dev/null || echo "N/A")
  [ "$PERSISTENT" != "N/A" ] && echo "  - Persistent: $PERSISTENT (will catch up on missed runs)"
else
  echo "  - Timer file not found at $TIMER_FILE"
fi
echo
echo "SCRIPT INFORMATION:"
echo "  - Script path: $SCRIPT_DIR/$PRINT_SCRIPT"
echo "  - PDF path: $PDF_PATH"
echo
echo "PRINTERS CONFIGURED:"
for printer in "${EPSON_PRINTERS[@]}"; do
  echo "  - $printer"
done
echo
echo "MANAGEMENT COMMANDS:"
echo "  - Check timer status: systemctl status $SERVICE_NAME.timer"
echo "  - Check timer schedule: systemctl list-timers"
echo "  - Run print job immediately: systemctl start $SERVICE_NAME.service"
echo "  - View service logs: journalctl -u $SERVICE_NAME.service"
echo "========================================================" 