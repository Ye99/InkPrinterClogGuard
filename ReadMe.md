# Inkjet Printer Glog Guard

Automatically prints a test page at scheduled intervals using systemd timers, to avoid inkjet heads from drying out.

To change the scheduled interval or when the test page is printed, edit the `print_test_page.timer` file, then rerun the setup script with the `--force` flag to overwrite the existing systemd timer. 

## Installation

Run the setup script with root privileges:
   ```
   sudo ./setup_print_test_page.sh
   ```

## Uninstallation

Run the setup script with the `--uninstall` flag:
   ```
   sudo ./setup_print_test_page.sh --uninstall
   ```
## show help

Run the setup script with the `--help` flag:
   ```
   ./setup_print_test_page.sh --help
   ```
