"""End-to-end install/uninstall of setup_print_test_page.sh with stubbed tools.

The script hardcodes /etc/systemd/system, so these tests write real files
there. They only run as root with INKGUARD_ROOT_TESTS=1 (CI runs them under
sudo on a throwaway runner). systemctl, apt, curl and timedatectl are stubs,
so no real service is enabled and no packages or timezone change.
"""

import os
import shutil
from pathlib import Path

import pytest

from tests.conftest import PRINT_SCRIPT, SETUP_SCRIPT

pytestmark = [
    pytest.mark.root,
    pytest.mark.skipif(
        os.geteuid() != 0 or os.environ.get("INKGUARD_ROOT_TESTS") != "1",
        reason="needs root and INKGUARD_ROOT_TESTS=1 (writes to /etc/systemd/system)",
    ),
]

UNIT_DIR = Path("/etc/systemd/system")
SERVICE = UNIT_DIR / "print_test_page.service"
TIMER = UNIT_DIR / "print_test_page.timer"


@pytest.fixture
def system(fake):
    if SERVICE.exists() or TIMER.exists():
        pytest.skip("print_test_page units already installed on this machine; not touching them")
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    yield fake
    SERVICE.unlink(missing_ok=True)
    TIMER.unlink(missing_ok=True)


def _system_timezone_is_utc() -> bool:
    tz = os.path.realpath("/etc/localtime").replace("/usr/share/zoneinfo/", "")
    return tz in ("UTC", "Etc/UTC")


def test_install_writes_units_and_enables_timer(system):
    result = system.run(SETUP_SCRIPT, "--printer-ip", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr

    script_path = system.workdir / PRINT_SCRIPT
    assert f"ExecStart={script_path}" in SERVICE.read_text()
    assert TIMER.read_text() == (system.workdir / "print_test_page.timer").read_text()
    assert SERVICE.stat().st_mode & 0o777 == 0o644
    assert TIMER.stat().st_mode & 0o777 == 0o644

    assert "PRINTERIP=10.0.1.99\n" in script_path.read_text()
    assert os.access(script_path, os.X_OK)

    cmds = system.commands()
    assert "apt update" in cmds
    assert "systemctl daemon-reload" in cmds
    assert "systemctl enable print_test_page.timer" in cmds
    assert "systemctl start print_test_page.timer" in cmds
    assert cmds.index("systemctl daemon-reload") < cmds.index("systemctl enable print_test_page.timer")


def test_install_adds_ipptool_when_missing(system):
    if shutil.which("ipptool", path="/usr/local/bin:/usr/bin:/bin"):
        pytest.skip("a real ipptool is installed, so the install branch can't be reached")
    (system.bin / "ipptool").unlink()
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "apt install -y cups-ipp-utils" in system.commands()


def test_second_install_needs_force(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0

    again = system.run(SETUP_SCRIPT, "-p", "10.0.1.98")
    assert again.returncode == 1
    assert "already installed" in again.stdout

    forced = system.run(SETUP_SCRIPT, "-p", "10.0.1.98", "--force")
    assert forced.returncode == 0, forced.stdout + forced.stderr
    assert "PRINTERIP=10.0.1.98\n" in (system.workdir / PRINT_SCRIPT).read_text()


def test_uninstall_removes_units(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    result = system.run(SETUP_SCRIPT, "--uninstall")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not SERVICE.exists()
    assert not TIMER.exists()
    cmds = system.commands()
    assert "systemctl stop print_test_page.timer" in cmds
    assert "systemctl disable print_test_page.timer" in cmds


@pytest.mark.skipif(not _system_timezone_is_utc(), reason="timezone detection only runs on UTC systems")
def test_utc_system_gets_detected_timezone(system):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", FAKE_CURL_OUTPUT="America/Los_Angeles")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "timedatectl set-timezone America/Los_Angeles" in system.commands()


@pytest.mark.skipif(not _system_timezone_is_utc(), reason="timezone detection only runs on UTC systems")
def test_utc_kept_when_detection_fails(system):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", FAKE_CURL_OUTPUT="")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not any(c.startswith("timedatectl") for c in system.commands())
