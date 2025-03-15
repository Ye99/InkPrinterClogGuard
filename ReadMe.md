# Inkjet Printer Clog Guard

Automatically prints a test page at scheduled intervals using systemd timers, to avoid inkjet heads from drying out.

Tested on Epson EcoTank ET-2850, should work for ET-3850, ET-4850 color inkjet printers as well. 

The default schedule is set to print a test page every 3 days. To change the scheduled interval or when the test page is printed, edit the `print_test_page.timer` file, then rerun the setup script with the `--force` flag to overwrite the existing systemd timer. 

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
