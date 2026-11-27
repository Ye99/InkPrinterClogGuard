"""Argument handling and pre-flight checks in setup_print_test_page.sh.

These tests put only the stub directory on PATH and leave systemctl out of it,
so even if a check regressed the script would stop at "systemd is not
available" before touching the system.
"""

import os

import pytest

from tests.conftest import SETUP_SCRIPT


@pytest.fixture
def isolated(fake):
    (fake.bin / "systemctl").unlink()
    fake.env_extra["PATH"] = str(fake.bin)
    return fake


def test_help_prints_usage(isolated):
    result = isolated.run(SETUP_SCRIPT, "--help")
    assert result.returncode == 0
    assert "Usage:" in result.stdout
    assert "--printer-ip" in result.stdout


def test_printer_ip_required_for_install(isolated):
    result = isolated.run(SETUP_SCRIPT)
    assert result.returncode == 1
    assert "Printer IP address is required" in result.stdout


@pytest.mark.parametrize("args", [["-p"], ["--printer-ip"], ["-p", "--force"]])
def test_printer_ip_option_needs_a_value(isolated, args):
    result = isolated.run(SETUP_SCRIPT, *args)
    assert result.returncode == 1
    assert "required after -p" in result.stdout


@pytest.mark.parametrize("ip", ["256.1.1.1", "10.0.1", "10.0.1.16.5", "printer.local", "10.0.1.x", "",
                                "010.0.1.1", "10.0.1.08", "10.0.1.00", "1000.0.0.1", " 10.0.1.16"])
def test_rejects_invalid_ip(isolated, ip):
    result = isolated.run(SETUP_SCRIPT, "--printer-ip", ip)
    assert result.returncode == 1
    if ip:
        assert "Invalid IP address format" in result.stdout


@pytest.mark.parametrize("ip", ["10.0.1.16", "192.168.1.255", "0.0.0.0", "255.255.255.255", "10.0.1.8",
                                "199.249.100.9"])
def test_accepts_valid_ip_and_moves_on_to_systemd_check(isolated, ip):
    result = isolated.run(SETUP_SCRIPT, "-p", ip)
    assert "Invalid IP" not in result.stdout
    assert "systemd is not available" in result.stdout
    assert result.returncode == 1


def test_leading_zero_error_explains_the_format(isolated):
    result = isolated.run(SETUP_SCRIPT, "-p", "10.0.1.08")
    assert result.returncode == 1
    assert "without leading zeros" in result.stdout
    assert "value too great for base" not in result.stderr


def test_rejects_unknown_option_and_shows_usage(isolated):
    result = isolated.run(SETUP_SCRIPT, "--bogus")
    assert result.returncode == 1
    assert "Unknown option: --bogus" in result.stdout
    assert "Usage:" in result.stdout


@pytest.mark.parametrize("zone", ["America/Los_Angeles", "UTC", "Asia/Taipei"])
def test_accepts_known_timezone(isolated, zone):
    result = isolated.run(SETUP_SCRIPT, "-p", "10.0.1.16", "--timezone", zone)
    assert "Unknown time zone" not in result.stdout
    assert "systemd is not available" in result.stdout


@pytest.mark.parametrize("zone", ["Mars/Olympus_Mons", "../../etc/passwd", "America/Los Angeles", "/etc/hosts"])
def test_rejects_unknown_timezone(isolated, zone):
    result = isolated.run(SETUP_SCRIPT, "-p", "10.0.1.16", "-t", zone)
    assert result.returncode == 1
    assert "Unknown time zone" in result.stdout


@pytest.mark.parametrize("args", [["-t"], ["--timezone"], ["--timezone", "--force"]])
def test_timezone_option_needs_a_value(isolated, args):
    result = isolated.run(SETUP_SCRIPT, "-p", "10.0.1.16", *args)
    assert result.returncode == 1
    assert "time zone is required" in result.stdout


def test_uninstall_does_not_need_printer_ip(isolated):
    result = isolated.run(SETUP_SCRIPT, "--uninstall")
    assert "Printer IP address is required" not in result.stdout
    assert "systemd is not available" in result.stdout


@pytest.mark.skipif(os.geteuid() == 0, reason="checks the non-root refusal, so must run as a normal user")
def test_refuses_to_install_without_root(fake):
    result = fake.run(SETUP_SCRIPT, "-p", "10.0.1.16")
    assert result.returncode == 1
    assert "must be run as root" in result.stdout
    assert not any(c.startswith(("apt", "systemctl")) for c in fake.commands())
