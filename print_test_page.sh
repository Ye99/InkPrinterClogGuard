#!/bin/bash
# Print the CUPS test page on your chosen printer
# lpstat -p to show available printers
# Schedule run this script every Monday 12PM:
# crontab -e
# 0 12 * * 1 cd /home/ye/p/configs && ./print_test_page.sh >> /home/ye/p/configs/cron.log 2>&1
#
# Below lpr doesn't work! Job gets stuck on both the Epson and Brother printers. 
# lpr -P EPSON_ET_2850_Series /usr/share/cups/data/default-testpage.pdf

# This lp works!
lp -d EPSON_ET_2850_Series my_anti_clog_print.pdf
