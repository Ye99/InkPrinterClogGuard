# Inkjet Printer Clog Guard

Automatically prints a test page at scheduled intervals using systemd timers, to avoid inkjet heads from drying out.

Tested on Epson EcoTank ET-2850, should work for ET-3850, ET-4850 color inkjet printers as well. 

# This project includes two services:
1. The setup_print_test_page.sh script sets up a service that prints an Epson nozzle check test page every Friday at noon. This helps save ink, although it may not prevent the color nozzles from becoming clogged. Increase the service's run frequency as needed.
1. The setup_cups_print_test.sh script sets up a service that prints an Ubuntu CUPS test page every Monday at noon. This test page uses more of the blue (B), cyan (C), yellow (Y), and magenta (M) inks.
I run both services so that Monday's test page uses more ink, and then, four days later on Friday, the test page uses less ink.

## 1. The Epson nozzle check test page 
The default schedule is set to print a test page every Friday at noon. To change the scheduled interval, edit the `print_test_page.timer` file. For example, instead of
```
OnCalendar=Fri 12:00
Persistent=true
```
this setting prints a test page on Monday and Friday at noon:
```
OnCalendar=Mon,Fri 12:00
Persistent=true
```
After making your changes, rerun the setup script with the --force flag to overwrite the existing systemd timer.

Note: I run this service on a virtualized Linux container 24/7. If you run this service on a computer that is powered off for extended periods, your inkjet printer may still get clogged because the service is not running.

### Installation

Run the setup script with root privileges, specifying your printer's IP address:
   ```
   sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16
   ```

The printer IP address parameter is mandatory and must be specified during installation.

### Changing Printer IP Address

If your printer's IP address changes, for instance changed from 10.0.1.16 to 10.0.1.17, update it by running:
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
## 2. The Ubuntu CUPS test page 
The CUPS test page prints a colorful test page that uses more ink than the Epson nozzle check.

### Prerequisites
- A Linux system with systemd

### Installation

1. Run the setup script with root privileges:
   ```
   sudo ./setup_cups_print_test.sh
   ```

The script will:
- Check if CUPS is installed and install it if needed
- Find all EPSON ET printers configured in your system
- Set up a systemd timer
- Start the timer immediately

### Uninstallation

Run the uninstall script with root privileges:
```
sudo ./uninstall_cups_print_test.sh
```

### Changing the Schedule

If you want to change the schedule, edit the `print_test_page_cups.timer` file before running the setup script. The default is 
```
 OnCalendar=Mon 12:00
```

After making changes, re-run the setup script to update the installed timer.

### Manually Triggering a Print

To print a test page immediately:
```
sudo systemctl start print_test_page_cups.service
```

### Checking Status

To check the status of the timer:
```
systemctl status print_test_page_cups.timer
```

To see when the next print job will run:
```
systemctl list-timers print_test_page_cups.timer
```

# Author

[Ye](https://github.com/Ye99)

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
