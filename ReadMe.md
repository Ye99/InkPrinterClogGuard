# Inkjet Printer Clog Guard

Prints an Epson nozzle-check page on a schedule, so the print head doesn't dry out and clog when the printer sits unused.

Inkjet heads clog when ink dries in the nozzles. A short print every few days keeps ink moving, and a nozzle-check page also shows at a glance whether any color has started to fail. This project installs a systemd timer on an always-on Linux machine (a home server, a container, a Raspberry Pi) that sends that page straight to the printer over the network. The printer doesn't need to be set up in CUPS.

Tested on the Epson EcoTank ET-2850. It should also work with the ET-3850, ET-4850 and similar Epson models. The page is Epson-specific printer data, so other brands won't print it.

## Requirements

- Linux with systemd, and root (`sudo`) for setup.
- `ipptool`. Setup installs it (package `cups-ipp-utils`) with `apt-get` when it's missing. On a distro without `apt-get`, install the package that provides `ipptool` first.
- The printer reachable from this machine over IPP (port 631), at a fixed IP address. A DHCP reservation in your router keeps the address from changing.
- systemd 235 or later, only if you use `--timezone`.

## Setup

Clone the repository somewhere it can stay, then run setup as root with your printer's IP address:

```
git clone https://github.com/Ye99/InkPrinterClogGuard.git
cd InkPrinterClogGuard
sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16
```

Setup copies `print_test_page.service` and `print_test_page.timer` to `/etc/systemd/system`, enables the timer and starts it. The installed service runs the print script from your clone, so don't move or delete the clone afterwards. If you do move it, re-run setup from the new location with `--force`.

Setup stores the printer address in the installed service (as `Environment=PRINTERIP=...`). It doesn't edit any file in the clone, so `git pull` stays clean.

| Option | What it does |
|---|---|
| `-p`, `--printer-ip IP` | The printer's IPv4 address, such as `10.0.1.16`. Required to install. Leading zeros (`010.0.1.16`) are rejected. |
| `-t`, `--timezone ZONE` | Run the schedule in this time zone, such as `America/Los_Angeles`, instead of the system's. Applies only to this timer. |
| `-f`, `--force` | Overwrite an existing install. Use it to change the IP, the time zone or the schedule. |
| `-u`, `--uninstall` | Remove the service and timer. |
| `-h`, `--help` | Show help. Doesn't need root. |

### Time zone

By default the schedule runs in the machine's time zone, and setup tells you which one that is. Setup never changes the system time zone.

If the machine runs on UTC (common in containers) and you want prints at local noon, pass a time zone name from `/usr/share/zoneinfo`:

```
sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16 --timezone America/Los_Angeles
```

Setup appends the zone to the timer's schedule, for example `OnCalendar=Mon,Fri 12:00 America/Los_Angeles`.

## Scheduling

The timer prints on Monday and Friday at 12:00. I've found that enough to keep my printer from clogging.

`Persistent=true` means a print missed while the machine was off runs once as soon as it's back on. A machine that is off for weeks still means weeks without a print, so this works best on a machine that runs all the time.

Check the last and next print times:

```
systemctl list-timers print_test_page.timer
```

See the installed schedule and printer address:

```
systemctl cat print_test_page.timer print_test_page.service
```

Read the output of past prints:

```
journalctl -u print_test_page.service
```

Print a page right now through the service, to check the install:

```
sudo systemctl start print_test_page.service
```

### Changing the schedule

Edit `OnCalendar=` in `print_test_page.timer` in your clone, then re-run setup with `--force`. For example, to print every other day at noon:

```
OnCalendar=*-*-01/2 12:00
```

Before you install a new schedule, `systemd-analyze calendar "*-*-01/2 12:00"` shows when it will next fire.

## How the print works

`self_contained_print_test_page.sh` carries everything it needs inside the script:

1. It unpacks two embedded files into a private temporary folder: an IPP Print-Job test file for `ipptool`, and Epson nozzle-check data captured from the Windows printer queue.
2. It puts a plain-text header with the current date and time in front of the nozzle-check data, so each page shows when it was printed.
3. It sends the result to `ipp://<printer>:631/ipp/print` with `ipptool`, waiting at most 60 seconds for a printer that is off or asleep.
4. It deletes the temporary folder and exits with `ipptool`'s result, so a failed print shows as a failed service run.

The service gives a print up to 5 minutes and then stops it, so a stuck job can't keep the unit running.

You can also run the script by hand, without the service and without root:

```
./self_contained_print_test_page.sh --printer-ip 10.0.1.16
```

## Upgrading

Pull the latest version, then re-run setup with `--force` so the installed units match:

```
git pull
sudo ./setup_print_test_page.sh --printer-ip 10.0.1.16 --force
```

Older versions wrote the printer IP into `self_contained_print_test_page.sh`. If `git pull` refuses because that file has local changes, discard them first with `git checkout -- self_contained_print_test_page.sh`.

## Changing the printer's IP address

```
sudo ./setup_print_test_page.sh --printer-ip 10.0.1.17 --force
```

## Uninstall

```
sudo ./setup_print_test_page.sh --uninstall
```

This stops and disables the timer and removes both units from `/etc/systemd/system`. It leaves `ipptool` and your clone in place.

## Running the tests

The tests are written in Python with pytest. They run both scripts against stub commands, so no printer is needed and nothing on the system changes.

```
python3 -m pip install -r requirements-dev.txt
python3 -m pytest
```

The install and uninstall tests write to `/etc/systemd/system`, so they run only as root and only when you ask for them. They stub `systemctl` and `apt-get`, and they skip themselves if this timer is already installed on the machine. CI runs them on a throwaway runner:

```
sudo env "PATH=$PATH" INKGUARD_ROOT_TESTS=1 python3 -m pytest -m root
```

CI (`.github/workflows/ci.yml`) runs ShellCheck on the scripts and both test sets on every pull request and on each push to `main`. To run ShellCheck locally:

```
shellcheck *.sh
```

## Troubleshooting

- **Nothing printed.** Run `journalctl -u print_test_page.service` and look for the `ipptool` error. A timeout or connection error usually means the printer is off, asleep or at another address. Running `./self_contained_print_test_page.sh --printer-ip <address>` by hand shows the same error right away.
- **"Service or timer already installed".** Add `--force` to replace the install.
- **"Invalid IP address format".** Use four numbers from 0 to 255 with no leading zeros, such as `10.0.1.16`.
- **"Unknown time zone".** Use a name that exists under `/usr/share/zoneinfo`, such as `Europe/London`.
- **"systemd doesn't accept the schedule".** Time zones in timers need systemd 235 or later. Leave out `--timezone`, or set the system time zone instead.
- **"ipptool is not installed and apt-get is unavailable".** Install the package that provides `ipptool` with your distro's package manager, then run setup again.
- **"no printer address" when running the script by hand.** Pass `--printer-ip`, or set `PRINTERIP`.
- **Prints at the wrong hour.** The schedule runs in the system time zone unless you used `--timezone`. Setup prints which zone it used. To change it, re-run setup with `--timezone` and `--force`.
- **The service fails after you moved the clone.** The installed service still points at the old path. Re-run setup with `--force` from the new location.

# Author

[Ye](https://github.com/Ye99)

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
