#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to update package repositories
update_packages() {
    print_info "Updating package lists..."
    if [ "$(id -u)" -eq 0 ]; then
        if ! apt update &>/dev/null; then
            print_error "Failed to update package lists. Check your internet connection."
        fi
    else
        if ! sudo apt update &>/dev/null; then
            print_error "Failed to update package lists. Check your internet connection."
        fi
    fi
    print_success "Package lists updated successfully."
}

# Function to install ipptool if not already installed
install_ipptool() {
    print_info "Checking if ipptool is installed..."
    if ! command -v ipptool &> /dev/null; then
        print_info "ipptool not found. Installing cups-ipp-utils..."
        if [ "$(id -u)" -eq 0 ]; then
            if ! apt install -y cups-ipp-utils; then
                print_error "Failed to install cups-ipp-utils. Please install it manually."
            fi
        else
            if ! sudo apt install -y cups-ipp-utils; then
                print_error "Failed to install cups-ipp-utils. Please install it manually."
            fi
        fi
        print_success "Successfully installed cups-ipp-utils"
    else
        print_info "ipptool is already installed."
    fi
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to print info messages
print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Function to print usage
print_usage() {
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -u, --uninstall Remove the service and timer"
    echo "  -f, --force     Force installation even if files already exist"
    echo ""
}

# Cleanup function
cleanup() {
    # Always clean up the temporary file if it exists
    if [ -n "$TMP_SERVICE_FILE" ] && [ -f "$TMP_SERVICE_FILE" ]; then
        rm -f "$TMP_SERVICE_FILE"
    fi
    
    if [ "$1" -ne 0 ] && [ "$INSTALLED_NEW_FILES" = "true" ]; then
        print_info "Cleaning up due to error..."
        rm -f /etc/systemd/system/print_test_page.service
        rm -f /etc/systemd/system/print_test_page.timer
        systemctl daemon-reload
    fi
}

# Default settings
UNINSTALL=false
FORCE=false
INSTALLED_NEW_FILES=false

# Parse command line arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Set up trap for cleanup on error
trap 'cleanup $?' EXIT

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    print_error "systemd is not available on this system."
fi

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root. Try using sudo."
fi

# Update package lists before anything else
update_packages

# Install ipptool if needed
install_ipptool

# Uninstall if requested
if [ "$UNINSTALL" = "true" ]; then
    print_info "Stopping print_test_page timer..."
    systemctl stop print_test_page.timer 2>/dev/null || true
    
    print_info "Disabling print_test_page timer..."
    systemctl disable print_test_page.timer 2>/dev/null || true
    
    print_info "Removing service and timer files..."
    rm -f /etc/systemd/system/print_test_page.service
    rm -f /etc/systemd/system/print_test_page.timer
    
    print_info "Reloading systemd daemon..."
    systemctl daemon-reload

    print_success "Uninstallation completed successfully!"
    exit 0
fi

# Check if service and timer files exist in current directory
if [ ! -f "print_test_page.service" ]; then
    print_error "print_test_page.service file not found in current directory."
fi

if [ ! -f "print_test_page.timer" ]; then
    print_error "print_test_page.timer file not found in current directory."
fi

# Get the current directory and use it to set the script path
CURRENT_DIR=$(pwd)
SCRIPT_PATH="$CURRENT_DIR/self_contained_print_test_page.sh"
print_info "Using script path: $SCRIPT_PATH"

# Create a temporary service file with the updated path
TMP_SERVICE_FILE=$(mktemp)
sed "s|ExecStart=.*|ExecStart=$SCRIPT_PATH|g" print_test_page.service > "$TMP_SERVICE_FILE"

# Check if files already exist in system directory
if [ -f "/etc/systemd/system/print_test_page.service" ] || [ -f "/etc/systemd/system/print_test_page.timer" ]; then
    if [ "$FORCE" = "true" ]; then
        print_info "Files already exist but force flag is set. Continuing..."
    else
        print_error "Service or timer already installed. Use --force to overwrite or --uninstall to remove first."
    fi
fi

# Copy files to systemd directory
print_info "Copying service and timer files to /etc/systemd/system/..."
cp "$TMP_SERVICE_FILE" /etc/systemd/system/print_test_page.service || print_error "Failed to copy service file."
cp print_test_page.timer /etc/systemd/system/ || print_error "Failed to copy timer file."
INSTALLED_NEW_FILES=true

# Remove temporary file
rm -f "$TMP_SERVICE_FILE"

# Set appropriate permissions
chmod 644 /etc/systemd/system/print_test_page.service || print_error "Failed to set permissions on service file."
chmod 644 /etc/systemd/system/print_test_page.timer || print_error "Failed to set permissions on timer file."
print_success "Files copied successfully with correct permissions."

# Reload systemd daemon
print_info "Reloading systemd daemon..."
systemctl daemon-reload || print_error "Failed to reload systemd daemon."
print_success "Systemd daemon reloaded."

# Enable and start the timer
print_info "Enabling print_test_page.timer..."
systemctl enable print_test_page.timer || print_error "Failed to enable timer."
print_success "Timer enabled."

print_info "Starting print_test_page.timer..."
systemctl start print_test_page.timer || print_error "Failed to start timer."
print_success "Timer started."

# List only the print_test_page timer for verification
print_info "Listing print_test_page timer for verification:"
systemctl list-timers print_test_page.timer | grep -v "Pass --all"

# Show timer information
print_info "Timer schedule information:"
systemctl cat print_test_page.timer | grep -E 'OnCalendar|OnBootSec|OnUnitActiveSec' | sed 's/^[[:space:]]*/    /'

print_success "Setup completed successfully! We will print a test page at the scheduled time."

# Clean exit (disables the trap)
trap - EXIT
exit 0 