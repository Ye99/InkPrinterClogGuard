#!/bin/bash
# Prints the same nozzle-check page as the Epson built-in test, with a timestamp
# header, straight to the printer over IPP. Run it from any Linux host; the host
# doesn't need the printer configured in CUPS, only ipptool (cups-ipp-utils).
#
# The printer address comes from --printer-ip (or -p), or else from the PRINTERIP
# environment variable. The systemd service that setup_print_test_page.sh
# installs sets PRINTERIP.

set -o pipefail

usage() {
    echo "Usage: $0 [--printer-ip IP]"
    echo "  -p, --printer-ip IP  Printer address (default: \$PRINTERIP)"
    echo "  -h, --help           Show this help message"
}

die() {
    echo >&2 "ERROR: $1"
    exit "${2:-1}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -p|--printer-ip)
            [ -n "${2:-}" ] || die "a printer address is required after $1" 2
            PRINTERIP=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown option: $1" 2
            ;;
    esac
done

if [ -z "${PRINTERIP:-}" ]; then
    die "no printer address. Pass --printer-ip IP, set PRINTERIP, or re-run setup_print_test_page.sh --printer-ip IP --force" 2
fi
# An IPv4 address or a host name; anything else would break the IPP URL.
if [[ ! $PRINTERIP =~ ^[A-Za-z0-9.-]+$ ]]; then
    die "invalid printer address: $PRINTERIP" 2
fi

if ! command -v ipptool &> /dev/null; then
    die "ipptool is required but not installed. Please run the setup script first."
fi

#--- embedded files, written to a private temp directory that is always removed
#
#       IPP_TEST_B64   /usr/share/cups/ipptool/print-job.test, which some distros don't ship
#       SPOOL_B64      Epson nozzle-check spool data captured from the Windows printer queue

IPP_TEST_B64='
H4sIAFDVhWQAA21Ry07DMBA8x1+xanvElbhxQxEKqEAfalPB1U02qaGxg70WIMS/s04fKVIv0WZ2
dndmPISF04ZAAaEnaFWNELw2NbQRl292I35EMoR8i2BUg2ArIK4jfTwei2SWTjMY7LdUencc7wD5
aDcDcRy3LTpF2hogyywUyXyRLdN8Mp/19I6dEjm9CXzjCjwpR3GjNt3hfkvtbGg7DQ/L+XrRd6Q6
zUtStUjSPF9CsVXOI1vtm0coUCVvDrSdMnWIMZzxjKLg1E6eemgO7OD0Pil0MtYj/hxaXVoOPwIn
xfolO3ayA0exPLAa3eAUS63y7xahtEVokJOorGsUwSgmStwRR5P8IJftRQ01Oihsq9HDNU/cT56z
/Yp4tkv2ZctbOVJiCR6UQ5g/3Ypklaf5egU+FAV6X4WdtO+XUalrYx2W0jrpw4atEQspzzT1d3qM
jcEnx/bVYkF8L3tdZHd5Z0aX/35jfr/iDwfmEbqXAgAA
'

SPOOL_B64='
H4sIAHvThWQAA2NgYJBmdHD18lEwNLIw0TPhArNBgEvaAQg1gjgYGIJcff1DXA1DPIFs9uds3HzK
zF7BLAwgIA3C6Ap9PYGSjAwMAQHMINo1ggOs1vj/f4YwTyaoLl4uFD1+ziAJHxeIJA+GmV6ujBAp
ANG//JOyAAAA
'

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/inkguard.XXXXXX") || die "can't create a temporary directory"
trap 'rm -rf "$WORKDIR"' EXIT

IPPTEMP="$WORKDIR/print-job.test"
SPLTEMP="$WORKDIR/nozzle-check.spl"
COMBINED_FILE="$WORKDIR/test-page.data"

printf '%s' "$IPP_TEST_B64" | base64 -di | gunzip > "$IPPTEMP" \
    || die "can't unpack the IPP test file"
printf '%s' "$SPOOL_B64" | base64 -di | gunzip > "$SPLTEMP" \
    || die "can't unpack the nozzle-check spool data"

#--- print: a plain-text header with the current time, then the nozzle check

CURRENT_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
{
    printf "\n\n\n\n====================================================\n        Test Page - Printed on: %s\n====================================================\n\n" "$CURRENT_DATETIME"
    cat "$SPLTEMP"
} > "$COMBINED_FILE" || die "can't write the test page"

# -T stops ipptool from waiting forever on a printer that is off or asleep.
ipptool -v -t -I -T 60 \
    -d filetype=application/octet-stream \
    -f "$(readlink -f "$COMBINED_FILE")" \
    "ipp://$PRINTERIP:631/ipp/print" \
    "$IPPTEMP"
RC=$?
[ "$RC" -eq 0 ] || echo >&2 "ERROR: ipptool rc=$RC (test page with header)"
exit "$RC"
