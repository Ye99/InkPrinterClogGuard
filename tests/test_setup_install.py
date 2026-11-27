"""End-to-end install/uninstall of setup_print_test_page.sh with stubbed tools.

The script hardcodes /etc/systemd/system, so these tests write real files
there. They only run as root with INKGUARD_ROOT_TESTS=1 (CI runs them under
sudo on a throwaway runner). systemctl, apt-get, curl and timedatectl are
stubs, so no real service is enabled and no packages or settings change.
"""

import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

from tests.conftest import BASH, PRINT_SCRIPT, REPO_ROOT, SETUP_SCRIPT, FakeSystem

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
def clean_units():
    if SERVICE.exists() or TIMER.exists():
        pytest.skip("print_test_page units already installed on this machine; not touching them")
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    yield
    SERVICE.unlink(missing_ok=True)
    TIMER.unlink(missing_ok=True)


@pytest.fixture
def system(fake, clean_units):
    return fake


def _new_commands(system, before: int) -> list[str]:
    return system.commands()[before:]


def _service_setting(key: str) -> str:
    values = [line.split("=", 1)[1] for line in SERVICE.read_text().splitlines() if line.startswith(key + "=")]
    assert len(values) == 1, f"expected one {key}= line, got {values}"
    return values[0]


def test_install_writes_units_and_enables_timer(system):
    result = system.run(SETUP_SCRIPT, "--printer-ip", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr

    script_path = system.workdir / PRINT_SCRIPT
    assert _service_setting("ExecStart") == f'/bin/bash "{script_path}"'
    assert _service_setting("Environment") == "PRINTERIP=10.0.1.99"
    assert "Type=oneshot" in SERVICE.read_text()
    assert TIMER.read_text() == (system.workdir / "print_test_page.timer").read_text()
    assert SERVICE.stat().st_mode & 0o777 == 0o644
    assert TIMER.stat().st_mode & 0o777 == 0o644

    cmds = system.commands()
    assert "systemctl daemon-reload" in cmds
    assert "systemctl enable print_test_page.timer" in cmds
    assert "systemctl restart print_test_page.timer" in cmds
    assert cmds.index("systemctl daemon-reload") < cmds.index("systemctl enable print_test_page.timer")


def test_install_leaves_the_tracked_print_script_unchanged(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    assert (system.workdir / PRINT_SCRIPT).read_bytes() == (REPO_ROOT / PRINT_SCRIPT).read_bytes()


def test_installed_service_prints_to_the_configured_printer(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    argv = shlex.split(_service_setting("ExecStart"))
    key, value = _service_setting("Environment").split("=", 1)

    before = len(system.commands())
    env = {"PATH": f"{system.bin}:/usr/bin:/bin", "FAKE_CMD_LOG": str(system.log),
           "FAKE_CAPTURE_DIR": str(system.capture), key: value}
    run = subprocess.run(argv, env=env, cwd="/", capture_output=True, text=True, timeout=60)
    assert run.returncode == 0, run.stderr
    calls = [c for c in _new_commands(system, before) if c.startswith("ipptool ")]
    assert len(calls) == 1 and "ipp://10.0.1.99:631/ipp/print" in calls[0]


def test_works_from_another_directory(system, tmp_path):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", cwd=tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    assert _service_setting("ExecStart") == f'/bin/bash "{system.workdir / PRINT_SCRIPT}"'


def test_quotes_paths_with_spaces_and_systemd_specifiers(tmp_path, clean_units):
    system = FakeSystem(tmp_path, "my clone 100% $HOME")
    system.stub_defaults()
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr
    expected = str(system.workdir / PRINT_SCRIPT).replace("%", "%%").replace("$", "$$")
    assert _service_setting("ExecStart") == f'/bin/bash "{expected}"'


def test_does_not_touch_apt_when_ipptool_is_present(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    assert not any(c.startswith(("apt", "apt-get")) for c in system.commands())


def test_install_adds_ipptool_when_missing(system):
    if shutil.which("ipptool", path="/usr/local/bin:/usr/bin:/bin"):
        pytest.skip("a real ipptool is installed, so the install branch can't be reached")
    (system.bin / "ipptool").unlink()
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr
    cmds = system.commands()
    assert cmds.index("apt-get update") < cmds.index("apt-get install -y cups-ipp-utils")


def test_clear_error_when_ipptool_missing_and_no_apt(system):
    (system.bin / "ipptool").unlink()
    (system.bin / "apt-get").unlink()
    # Only the stub dir on PATH (plus dirname), so a real ipptool or apt-get can't be found.
    (system.bin / "dirname").symlink_to(shutil.which("dirname"))
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", PATH=str(system.bin))
    assert result.returncode == 1
    assert "apt-get is unavailable" in result.stdout
    assert not SERVICE.exists()


def test_second_install_needs_force(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0

    again = system.run(SETUP_SCRIPT, "-p", "10.0.1.98")
    assert again.returncode == 1
    assert "already installed" in again.stdout
    assert _service_setting("Environment") == "PRINTERIP=10.0.1.99"

    forced = system.run(SETUP_SCRIPT, "-p", "10.0.1.98", "--force")
    assert forced.returncode == 0, forced.stdout + forced.stderr
    assert _service_setting("Environment") == "PRINTERIP=10.0.1.98"


def test_already_installed_check_comes_before_installing_packages(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    (system.bin / "ipptool").unlink()
    before = len(system.commands())
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.98").returncode == 1
    assert not any(c.startswith("apt") for c in _new_commands(system, before))


def test_failed_fresh_install_is_rolled_back(system):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", FAKE_SYSTEMCTL_RC=1)
    assert result.returncode == 1
    assert "Cleaning up due to error" in result.stdout
    assert not SERVICE.exists()
    assert not TIMER.exists()


def test_failed_force_reinstall_keeps_the_existing_units(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.98", "--force", FAKE_SYSTEMCTL_RC=1)
    assert result.returncode == 1
    assert SERVICE.exists()
    assert TIMER.exists()


def test_uninstall_removes_units(system):
    assert system.run(SETUP_SCRIPT, "-p", "10.0.1.99").returncode == 0
    result = system.run(SETUP_SCRIPT, "--uninstall")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not SERVICE.exists()
    assert not TIMER.exists()
    cmds = system.commands()
    assert "systemctl stop print_test_page.timer" in cmds
    assert "systemctl disable print_test_page.timer" in cmds


def test_never_changes_the_system_timezone_or_calls_the_network(system):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99")
    assert result.returncode == 0, result.stdout + result.stderr
    cmds = system.commands()
    assert not any(c.startswith("curl") for c in cmds)
    assert not any(c.startswith("timedatectl set-timezone") for c in cmds)


def test_timezone_option_is_applied_to_the_timer_schedule(system):
    result = system.run(SETUP_SCRIPT, "-p", "10.0.1.99", "--timezone", "America/Los_Angeles")
    assert result.returncode == 0, result.stdout + result.stderr
    schedules = re.findall(r"^OnCalendar=(.*)$", TIMER.read_text(), re.M)
    assert schedules == ["Mon,Fri 12:00 America/Los_Angeles"]
    if shutil.which("systemd-analyze"):
        check = subprocess.run(["systemd-analyze", "calendar", schedules[0]], capture_output=True, text=True)
        assert check.returncode == 0, check.stderr
    assert not any(c.startswith("timedatectl set-timezone") for c in system.commands())


def test_utc_system_gets_a_hint_about_timezone(system):
    result = subprocess.run([BASH, "-c", "readlink -f /etc/localtime"], capture_output=True, text=True)
    if result.stdout.strip() not in ("/usr/share/zoneinfo/UTC", "/usr/share/zoneinfo/Etc/UTC"):
        pytest.skip("only UTC systems get the hint")
    out = system.run(SETUP_SCRIPT, "-p", "10.0.1.99")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "--timezone" in out.stdout
