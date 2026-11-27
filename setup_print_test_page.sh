#!/bin/bash
# Installs (or removes) a systemd timer that prints an Epson nozzle-check page
# on a schedule, so the print head doesn't dry out. Run as root from anywhere;
# the scripts and unit files are taken from this script's own directory.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PRINT_SCRIPT="$SCRIPT_DIR/self_contained_print_test_page.sh"
SERVICE_NAME=print_test_page.service
TIMER_NAME=print_test_page.timer
UNIT_DIR=/etc/systemd/system
ZONEINFO_DIR=/usr/share/zoneinfo

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
    echo "  -h, --help             Show this help message"
    echo "  -u, --uninstall        Remove the service and timer"
    echo "  -f, --force            Force installation even if files already exist"
    echo "  -p, --printer-ip IP    Set the printer IP address (e.g. 10.0.1.16)"
    echo "  -t, --timezone ZONE    Run the schedule in this time zone (e.g. America/Los_Angeles)"
    echo "                         instead of the system time zone"
    echo ""
}

# An IPv4 address with each octet 0-255 and no leading zeros. Leading zeros are
# rejected because tools disagree on whether 010 means 10 or 8 (octal).
validate_ip() {
    local octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
    [[ $1 =~ ^$octet\.$octet\.$octet\.$octet$ ]]
}

# A tz database name such as America/Los_Angeles that exists on this system.
validate_timezone() {
    [[ $1 =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] && [ -f "$ZONEINFO_DIR/$1" ]
}

# Quote a path for an ExecStart= line, so spaces and systemd specifiers are safe.
systemd_quote() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//%/%%}
    s=${s//\$/\$\$}
    printf '"%s"' "$s"
}

# Install ipptool if it isn't already there. Only touches apt when needed.
install_ipptool() {
    print_info "Checking if ipptool is installed..."
    if command -v ipptool &> /dev/null; then
        print_info "ipptool is already installed."
        return 0
    fi
    if ! command -v apt-get &> /dev/null; then
        print_error "ipptool is not installed and apt-get is unavailable. Install the package that provides ipptool (cups-ipp-utils on Debian/Ubuntu), then run this again."
    fi
    print_info "ipptool not found. Updating package lists..."
    if ! apt-get update; then
        print_error "Failed to update package lists. Check your internet connection."
    fi
    print_info "Installing cups-ipp-utils..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y cups-ipp-utils; then
        print_error "Failed to install cups-ipp-utils. Please install it manually."
    fi
    print_success "Successfully installed cups-ipp-utils"
}

# Tell the user what time zone the schedule runs in. Never changes the system.
report_timezone() {
    if [ -n "$TIMEZONE" ]; then
        print_info "The schedule will run in time zone $TIMEZONE."
        return 0
    fi
    local current_tz
    current_tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    if [ -z "$current_tz" ]; then
        current_tz=$(readlink -f /etc/localtime 2>/dev/null)
        case "$current_tz" in
            "$ZONEINFO_DIR"/*) current_tz=${current_tz#"$ZONEINFO_DIR"/} ;;
            *) current_tz="" ;;
        esac
    fi
    if [ -z "$current_tz" ]; then
        print_info "Couldn't tell the system time zone. The schedule in $TIMER_NAME runs in it; use --timezone (for example --timezone America/Los_Angeles) to pick one."
    elif [ "$current_tz" = "UTC" ] || [ "$current_tz" = "Etc/UTC" ]; then
        print_info "The system time zone is UTC, so the schedule in $TIMER_NAME runs in UTC. To use local time, re-run with --timezone (for example --timezone America/Los_Angeles) and --force."
    else
        print_info "The schedule will run in the system time zone: $current_tz."
    fi
}

# The service unit to install: ExecStart points at this clone's print script and
# PRINTERIP is passed in the environment, so the tracked script isn't edited.
render_service() {
    local line found=false
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^[[:space:]]*ExecStart= ]]; then
            printf 'ExecStart=/bin/bash %s\n' "$(systemd_quote "$PRINT_SCRIPT")"
            printf 'Environment=PRINTERIP=%s\n' "$PRINTER_IP"
            found=true
        elif [[ $line =~ ^[[:space:]]*Environment=PRINTERIP= ]]; then
            continue
        else
            printf '%s\n' "$line"
        fi
    done < "$SCRIPT_DIR/$SERVICE_NAME"
    [ "$found" = "true" ]
}

# The timer unit to install, with --timezone appended to each OnCalendar= line.
render_timer() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$TIMEZONE" ] && [[ $line =~ ^[[:space:]]*OnCalendar=.+ ]]; then
            printf '%s %s\n' "$line" "$TIMEZONE"
        else
            printf '%s\n' "$line"
        fi
    done < "$SCRIPT_DIR/$TIMER_NAME"
}

# Cleanup function, run from the EXIT trap
# shellcheck disable=SC2317,SC2329
cleanup() {
    rm -f "$TMP_SERVICE_FILE" "$TMP_TIMER_FILE"

    # Roll back a failed fresh install. A failed --force reinstall leaves the
    # files in place, since removing them would also remove the old, working setup.
    if [ "$1" -ne 0 ] && [ "$INSTALLED_NEW_FILES" = "true" ] && [ "$WAS_INSTALLED" = "false" ]; then
        print_info "Cleaning up due to error..."
        systemctl disable "$TIMER_NAME" 2>/dev/null
        rm -f "$UNIT_DIR/$SERVICE_NAME" "$UNIT_DIR/$TIMER_NAME"
        systemctl daemon-reload
    fi
}

# Default settings
UNINSTALL=false
FORCE=false
INSTALLED_NEW_FILES=false
WAS_INSTALLED=false
PRINTER_IP=""
TIMEZONE=""
TMP_SERVICE_FILE=""
TMP_TIMER_FILE=""

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
        -p|--printer-ip)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                print_error "Printer IP address is required after -p or --printer-ip option."
            fi
            PRINTER_IP="$2"
            if ! validate_ip "$PRINTER_IP"; then
                print_error "Invalid IP address format: $PRINTER_IP (use four numbers 0-255 without leading zeros, e.g. 10.0.1.16)"
            fi
            shift 2
            ;;
        -t|--timezone)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                print_error "A time zone is required after -t or --timezone option."
            fi
            TIMEZONE="$2"
            if ! validate_timezone "$TIMEZONE"; then
                print_error "Unknown time zone: $TIMEZONE (use a name from $ZONEINFO_DIR, e.g. America/Los_Angeles)"
            fi
            shift 2
            ;;
        *)
            print_usage
            print_error "Unknown option: $1"
            ;;
    esac
done

# Set up trap for cleanup on error
trap 'cleanup $?' EXIT

# Printer IP is required unless uninstalling
if [ "$UNINSTALL" != "true" ] && [ -z "$PRINTER_IP" ]; then
    print_error "Printer IP address is required. Use --printer-ip option. For example: sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16"
fi

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    print_error "systemd is not available on this system."
fi

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root. Try using sudo."
fi

# Uninstall if requested
if [ "$UNINSTALL" = "true" ]; then
    print_info "Stopping print_test_page timer..."
    systemctl stop "$TIMER_NAME" 2>/dev/null || true

    print_info "Disabling print_test_page timer..."
    systemctl disable "$TIMER_NAME" 2>/dev/null || true

    print_info "Removing service and timer files..."
    rm -f "$UNIT_DIR/$SERVICE_NAME" "$UNIT_DIR/$TIMER_NAME"

    print_info "Reloading systemd daemon..."
    systemctl daemon-reload

    print_success "Uninstallation completed successfully!"
    exit 0
fi

# Pre-flight checks, before anything on the system changes.
for f in "$PRINT_SCRIPT" "$SCRIPT_DIR/$SERVICE_NAME" "$SCRIPT_DIR/$TIMER_NAME"; do
    if [ ! -f "$f" ]; then
        print_error "$(basename "$f") not found in $SCRIPT_DIR."
    fi
done

if [[ $PRINT_SCRIPT == *$'\n'* ]]; then
    print_error "The path to this folder contains a line break, which systemd can't use: $SCRIPT_DIR"
fi

if [ -f "$UNIT_DIR/$SERVICE_NAME" ] || [ -f "$UNIT_DIR/$TIMER_NAME" ]; then
    WAS_INSTALLED=true
    if [ "$FORCE" = "true" ]; then
        print_info "Files already exist but force flag is set. Continuing..."
    else
        print_error "Service or timer already installed. Use --force to overwrite or --uninstall to remove first."
    fi
fi

# Install ipptool if needed
install_ipptool

report_timezone

print_info "Using script path: $PRINT_SCRIPT"
print_info "Using printer IP address: $PRINTER_IP"

TMP_SERVICE_FILE=$(mktemp) || print_error "Failed to create a temporary file."
TMP_TIMER_FILE=$(mktemp) || print_error "Failed to create a temporary file."
render_service > "$TMP_SERVICE_FILE" || print_error "No ExecStart= line found in $SERVICE_NAME."
render_timer > "$TMP_TIMER_FILE" || print_error "Failed to prepare $TIMER_NAME."

# With --timezone, check that this systemd understands each schedule (time
# zones in OnCalendar= need systemd 235 or later).
if [ -n "$TIMEZONE" ] && command -v systemd-analyze &> /dev/null; then
    while IFS= read -r calendar; do
        if ! systemd-analyze calendar "$calendar" &> /dev/null; then
            print_error "systemd doesn't accept the schedule \"$calendar\". Time zones in timers need systemd 235 or later."
        fi
    done < <(sed -n 's/^[[:space:]]*OnCalendar=//p' "$TMP_TIMER_FILE")
fi

# Copy files to systemd directory with the right permissions
print_info "Copying service and timer files to $UNIT_DIR/..."
INSTALLED_NEW_FILES=true
install -m 0644 "$TMP_SERVICE_FILE" "$UNIT_DIR/$SERVICE_NAME" || print_error "Failed to copy service file."
install -m 0644 "$TMP_TIMER_FILE" "$UNIT_DIR/$TIMER_NAME" || print_error "Failed to copy timer file."
print_success "Files copied successfully with correct permissions."

# Reload systemd daemon
print_info "Reloading systemd daemon..."
systemctl daemon-reload || print_error "Failed to reload systemd daemon."
print_success "Systemd daemon reloaded."

# Enable and (re)start the timer, so a --force reinstall picks up a new schedule
print_info "Enabling $TIMER_NAME..."
systemctl enable "$TIMER_NAME" || print_error "Failed to enable timer."
print_success "Timer enabled."

print_info "Starting $TIMER_NAME..."
systemctl restart "$TIMER_NAME" || print_error "Failed to start timer."
print_success "Timer started."

# List only the print_test_page timer for verification
print_info "Listing print_test_page timer for verification:"
systemctl list-timers "$TIMER_NAME" | grep -v "Pass --all"

# Show timer information
print_info "Timer schedule information:"
systemctl cat "$TIMER_NAME" | grep -E 'OnCalendar|OnBootSec|OnUnitActiveSec' | sed 's/^[[:space:]]*/    /'

print_success "Setup completed successfully! We will print a test page at the scheduled time."

# Clean exit (disables the trap)
rm -f "$TMP_SERVICE_FILE" "$TMP_TIMER_FILE"
trap - EXIT
exit 0
