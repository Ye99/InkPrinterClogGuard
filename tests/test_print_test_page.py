"""Tests for self_contained_print_test_page.sh with ipptool stubbed out."""

import re
import threading

import pytest

from tests.conftest import PRINT_SCRIPT


@pytest.fixture
def printer(fake, tmp_path):
    """The fake system with a printer address and a private TMPDIR to check cleanup."""
    tmpdir = tmp_path / "tmp"
    tmpdir.mkdir()
    fake.env_extra["PRINTERIP"] = "10.0.1.16"
    fake.env_extra["TMPDIR"] = str(tmpdir)
    fake.tmpdir = tmpdir
    return fake


def _ipptool_calls(fake) -> list[str]:
    return [c for c in fake.commands() if c.startswith("ipptool ")]


def test_fails_cleanly_when_ipptool_missing(printer):
    (printer.bin / "ipptool").unlink()
    # Only the stub dir on PATH: the script must stop at its ipptool check.
    result = printer.run(PRINT_SCRIPT, PATH=str(printer.bin))
    assert result.returncode == 1
    assert "ipptool is required" in result.stderr
    assert printer.commands() == []


def test_sends_print_job_to_configured_printer(printer):
    result = printer.run(PRINT_SCRIPT)
    assert result.returncode == 0, result.stderr

    calls = _ipptool_calls(printer)
    assert len(calls) == 1
    call = calls[0]
    assert "ipp://10.0.1.16:631/ipp/print" in call
    assert "-d filetype=application/octet-stream" in call
    assert call.split()[1:4] == ["-v", "-t", "-I"]


def test_ipptool_has_a_timeout(printer):
    printer.run(PRINT_SCRIPT)
    assert re.search(r" -T \d+ ", _ipptool_calls(printer)[0])


def test_printer_ip_from_environment(printer):
    result = printer.run(PRINT_SCRIPT, PRINTERIP="192.168.7.42")
    assert result.returncode == 0, result.stderr
    assert "ipp://192.168.7.42:631/ipp/print" in _ipptool_calls(printer)[0]


@pytest.mark.parametrize("flag", ["-p", "--printer-ip"])
def test_printer_ip_option_overrides_environment(printer, flag):
    result = printer.run(PRINT_SCRIPT, flag, "192.168.7.43")
    assert result.returncode == 0, result.stderr
    assert "ipp://192.168.7.43:631/ipp/print" in _ipptool_calls(printer)[0]


def test_fails_without_printer_address(printer):
    del printer.env_extra["PRINTERIP"]
    result = printer.run(PRINT_SCRIPT)
    assert result.returncode == 2
    assert "no printer address" in result.stderr
    assert _ipptool_calls(printer) == []


@pytest.mark.parametrize("address", ["10.0.1.16/evil", "10.0.1.16 -x", "a:b"])
def test_rejects_printer_address_that_would_break_the_url(printer, address):
    result = printer.run(PRINT_SCRIPT, PRINTERIP=address)
    assert result.returncode == 2
    assert "invalid printer address" in result.stderr
    assert _ipptool_calls(printer) == []


def test_unknown_option_shows_usage(printer):
    result = printer.run(PRINT_SCRIPT, "--bogus")
    assert result.returncode == 2
    assert "Usage:" in result.stderr
    assert "unknown option: --bogus" in result.stderr


def test_ipp_test_file_is_a_print_job_request(printer):
    printer.run(PRINT_SCRIPT)
    ipp_test = (printer.capture / "ipp-test-file").read_text()
    assert "OPERATION Print-Job" in ipp_test
    assert "FILE $filename" in ipp_test
    assert "EXPECT job-id" in ipp_test


def test_document_is_timestamp_header_followed_by_nozzle_check_spool(printer):
    printer.run(PRINT_SCRIPT)
    document = (printer.capture / "document").read_bytes()

    header, sep, spool = document.partition(b"====================================================\n\n")
    assert sep, "header banner missing"
    assert re.search(rb"Test Page - Printed on: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", header)
    # Epson remote-mode spool data: EJL preamble and the nozzle-check ("NC") command.
    assert spool.startswith(b"\x00\x00\x00\x1b\x01@EJL")
    assert b"REMOTE1NC" in spool


def test_removes_temp_files_after_success(printer):
    assert printer.run(PRINT_SCRIPT).returncode == 0
    assert list(printer.tmpdir.iterdir()) == []


def test_propagates_ipptool_failure_and_still_cleans_up(printer):
    result = printer.run(PRINT_SCRIPT, FAKE_IPPTOOL_RC=3)
    assert result.returncode == 3
    assert "ipptool rc=3" in result.stderr
    assert list(printer.tmpdir.iterdir()) == []


def test_each_run_uses_its_own_temp_files(printer):
    """Two runs at once must not share (and delete) each other's files."""
    slow_ipptool = (printer.bin / "ipptool").read_text().replace(
        'exit "${FAKE_IPPTOOL_RC:-0}"', 'sleep 0.5\nexit "${FAKE_IPPTOOL_RC:-0}"'
    )
    printer.stub("ipptool", slow_ipptool)
    results = []

    def run():
        results.append(printer.run(PRINT_SCRIPT))

    threads = [threading.Thread(target=run) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert [r.returncode for r in results] == [0, 0], [r.stderr for r in results]
    test_files = [c.split()[-1] for c in _ipptool_calls(printer)]
    assert len(set(test_files)) == 2
    assert list(printer.tmpdir.iterdir()) == []
