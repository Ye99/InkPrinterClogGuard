"""Static checks on the shipped systemd unit files."""

import configparser
import shutil
import subprocess

import pytest

from tests.conftest import REPO_ROOT


def _load(name: str) -> configparser.ConfigParser:
    parser = configparser.ConfigParser(strict=False, interpolation=None)
    parser.optionxform = str  # systemd keys are case-sensitive
    # The service file indents every line; strip it before parsing.
    text = "\n".join(line.strip() for line in (REPO_ROOT / name).read_text().splitlines())
    parser.read_string(text)
    return parser


def test_service_runs_the_print_script():
    service = _load("print_test_page.service")
    assert service["Service"]["ExecStart"].endswith("/self_contained_print_test_page.sh")


def test_timer_targets_the_service_and_persists_missed_runs():
    timer = _load("print_test_page.timer")
    assert timer["Timer"]["Unit"] == "print_test_page.service"
    assert timer["Timer"]["Persistent"] == "true"
    assert timer["Install"]["WantedBy"] == "timers.target"


@pytest.mark.skipif(shutil.which("systemd-analyze") is None, reason="systemd-analyze not installed")
def test_timer_schedule_is_a_valid_calendar_expression():
    expr = _load("print_test_page.timer")["Timer"]["OnCalendar"]
    result = subprocess.run(["systemd-analyze", "calendar", expr], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_service_is_a_oneshot_job_that_waits_for_the_network():
    service = _load("print_test_page.service")
    assert service["Service"]["Type"] == "oneshot"
    assert "network-online.target" in service["Unit"]["After"]
    assert "network-online.target" in service["Unit"]["Wants"]


def test_service_has_a_start_timeout():
    # Type=oneshot has no start timeout by default, so a hung job would never end.
    assert _load("print_test_page.service")["Service"]["TimeoutStartSec"]
