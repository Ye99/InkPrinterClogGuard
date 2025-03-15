# Inkjet Printer Clog Guard

Automatically prints a test page at scheduled intervals using systemd timers, to avoid inkjet heads from drying out.

Tested on Epson EcoTank ET-2850, should work for ET-3850, ET-4850 color inkjet printers as well. 

The default schedule is set to print a test page every 3 days. To change the scheduled interval, edit the `print_test_page.timer` file, then rerun the setup script with the `--force` flag to overwrite the existing systemd timer. 

Note: I run this service on a virtualized Linux container 24/7, so I use the following systemd timer settings. The OnBootSec=1min setting prints a test page 1 minute after reboot, which is required to kick off the first run on a new container.
```
# This ensures the first run happens right away on boot, and then every 3 days after that.
OnBootSec=1min
# Run every 3 days
OnUnitActiveSec=3d
```
However, if you run this service on a computer that you power off and on frequently, the above settings will cause unnecessary extra executions. Instead, use the following settings:
```
OnCalendar=Mon,Fri 12:00
Persistent=true
```

## Installation

Run the setup script with root privileges, specifying your printer's IP address:
   ```
   sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16
   ```

The printer IP address parameter is mandatory and must be specified during installation.

## Changing Printer IP Address

If your printer's IP address changes, for instance changed from 10.0.1.16 to 10.0.1.17, update it by running:
   ```
   sudo ./setup_print_test_page.sh --printer-ip 10.0.1.17 --force
   ```

## Uninstallation

Run the setup script with the `--uninstall` flag:
   ```
   sudo ./setup_print_test_page.sh --uninstall
   ```

## Show Help

Run the setup script with the `--help` flag:
   ```
   ./setup_print_test_page.sh --help
   ```

## Author

[Ye](https://github.com/Ye99)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
