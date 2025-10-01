# Inkjet Printer Clog Guard

Automatically prints test pages at scheduled times using Linux systemd timers to prevent inkjet heads from drying out.

Tested on the Epson EcoTank ET-2850; it should also work with the ET-3850, ET-4850, and similar models.

### How to change print frequency
The `setup_print_test_page.sh` script sets up a Linux service that prints an Epson nozzle check test page on Monday and Friday at noon. I've found this schedule to be sufficient. To increase the print frequency, edit the `print_test_page.timer` file and replace:
```
OnCalendar=Mon,Fri 12:00
Persistent=true
```
use this to print every other day at noon:
```
OnCalendar=*-*-01/2 12:00
Persistent=true
```
After making your changes, re-run the setup script with the --force flag to overwrite the existing systemd timer.

Note: I run this service in a Linux container on a home server that runs 24/7. If your computer is powered off for extended periods, your inkjet printer may still clog because scheduled prints are skipped during downtime.

### Installation

Run the setup script with root privileges, specifying your printer's IP address:
   ```
   sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16
   ```

### Test your installation to verify it works as expected
Print a test page immediately through the service:
```
sudo systemctl start print_test_page.service
```

### Check the timer status
```
systemctl status print_test_page.timer
```

See the next scheduled run time:
```
systemctl list-timers print_test_page.timer
```

### Changing Printer IP Address

If your printer's IP address changes (e.g., from 10.0.1.16 to 10.0.1.17), update it by running:
   ```
   sudo ./setup_print_test_page.sh --printer-ip 10.0.1.17 --force
   ```

### Uninstallation

Run the setup script with the `--uninstall` flag:
   ```
   sudo ./setup_print_test_page.sh --uninstall
   ```

### Show Help

Run the setup script with the `--help` flag:
   ```
   ./setup_print_test_page.sh --help
   ```
# Author

[Ye](https://github.com/Ye99)

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
