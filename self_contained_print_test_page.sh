#!/bin/bash
# This prints test page same as Epson built-in test page, with latest statics. 
# Run this script from any Linux, and the Linux host doesn't need the printer configured in CUPS 
# Check if ipptool is installed
if ! command -v ipptool &> /dev/null; then
    echo "ERROR: ipptool is required but not installed. Please run the setup script first."
    exit 1
fi
PRINTERIP=10.0.1.16

#--- extract embedded spool files
#
#       $SPLTEMP        SPL file grabbed from Windows printer queue after using Epson printer dialog
#       $IPPTEMP        /usr/share/cups/ipptool/print-job.test comes with Mint 19.x but not with CentOS7

SPLTEMP="/tmp/epson-p900-nozzlecheck.$$.spl"
IPPTEMP="/tmp/cups-ipptool-print-job.test"

# Get current date and time
CURRENT_DATETIME=$(date "+%Y-%m-%d %H:%M:%S")

# Define combined file with header and test page content
COMBINED_FILE="/tmp/combined-test-page.$$.data"

cat << EOF | base64 -di | gunzip > "$IPPTEMP"
H4sIAFDVhWQAA21Ry07DMBA8x1+xanvElbhxQxEKqEAfalPB1U02qaGxg70WIMS/s04fKVIv0WZ2
dndmPISF04ZAAaEnaFWNELw2NbQRl292I35EMoR8i2BUg2ArIK4jfTwei2SWTjMY7LdUencc7wD5
aDcDcRy3LTpF2hogyywUyXyRLdN8Mp/19I6dEjm9CXzjCjwpR3GjNt3hfkvtbGg7DQ/L+XrRd6Q6
zUtStUjSPF9CsVXOI1vtm0coUCVvDrSdMnWIMZzxjKLg1E6eemgO7OD0Pil0MtYj/hxaXVoOPwIn
xfolO3ayA0exPLAa3eAUS63y7xahtEVokJOorGsUwSgmStwRR5P8IJftRQ01Oihsq9HDNU/cT56z
/Yp4tkv2ZctbOVJiCR6UQ5g/3Ypklaf5egU+FAV6X4WdtO+XUalrYx2W0jrpw4atEQspzzT1d3qM
jcEnx/bVYkF8L3tdZHd5Z0aX/35jfr/iDwfmEbqXAgAA
EOF

cat << EOF | base64 -di | gunzip > "$SPLTEMP"
H4sIAHvThWQAA2NgYJBmdHD18lEwNLIw0TPhArNBgEvaAQg1gjgYGIJcff1DXA1DPIFs9uds3HzK
zF7BLAwgIA3C6Ap9PYGSjAwMAQHMINo1ggOs1vj/f4YwTyaoLl4uFD1+ziAJHxeIJA+GmV6ujBAp
ANG//JOyAAAA
EOF

#--- print

# Create header with current date/time as plain text
HEADER_FILE="/tmp/header.$$.txt"
printf "\n\n\n\n====================================================\n        Test Page - Printed on: %s\n====================================================\n\n" "$CURRENT_DATETIME" > "$HEADER_FILE"

# Combine the header with the test page content into one file
cat "$HEADER_FILE" > "$COMBINED_FILE"
cat "$SPLTEMP" >> "$COMBINED_FILE"
rm -f "$HEADER_FILE"

if [ -e "$IPPTEMP" -a -e "$COMBINED_FILE" ] ; then
  ipptool -v -t -I \
    -d filetype=application/octet-stream \
    -f "$(readlink -f "$COMBINED_FILE")" \
    ipp://$PRINTERIP:631/ipp/print \
    "$IPPTEMP"
  RC=$?
  [ "$RC" == "0" ] || echo >&2 "ERROR: ipptool rc=$RC (test page with header)"
else
  echo >&2 "ERROR: can't create temporary files"
  RC=1
fi

#--- cleanup

rm "$IPPTEMP" "$SPLTEMP" "$COMBINED_FILE"
exit $RC