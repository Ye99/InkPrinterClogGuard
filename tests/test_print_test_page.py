"""Tests for self_contained_print_test_page.sh with ipptool stubbed out."""

import re
from pathlib import Path

from tests.conftest import PRINT_SCRIPT

TMP = Path("/tmp")


def _leftover_temp_files() -> set[Path]:
    patterns = ["epson-p900-nozzlecheck.*.spl", "combined-test-page.*.data", "header.*.txt",
                "cups-ipptool-print-job.test"]
    return {p for pattern in patterns for p in TMP.glob(pattern)}


def test_fails_cleanly_when_ipptool_missing(fake):
    (fake.bin / "ipptool").unlink()
    # Only the stub dir on PATH: the script must stop at its ipptool check.
    result = fake.run(PRINT_SCRIPT, PATH=str(fake.bin))
    assert result.returncode == 1
    assert "ipptool is required" in result.stdout
    assert fake.commands() == []


def test_sends_print_job_to_configured_printer(fake):
    result = fake.run(PRINT_SCRIPT)
    assert result.returncode == 0, result.stderr

    calls = [c for c in fake.commands() if c.startswith("ipptool ")]
    assert len(calls) == 1
    call = calls[0]
    assert "ipp://10.0.1.16:631/ipp/print" in call
    assert "-d filetype=application/octet-stream" in call
    assert call.split()[1:4] == ["-v", "-t", "-I"]


def test_uses_printer_ip_from_script(fake):
    script = fake.workdir / PRINT_SCRIPT
    script.write_text(script.read_text().replace("PRINTERIP=10.0.1.16", "PRINTERIP=192.168.7.42"))
    result = fake.run(PRINT_SCRIPT)
    assert result.returncode == 0, result.stderr
    assert "ipp://192.168.7.42:631/ipp/print" in fake.commands()[0]


def test_ipp_test_file_is_a_print_job_request(fake):
    fake.run(PRINT_SCRIPT)
    ipp_test = (fake.capture / "ipp-test-file").read_text()
    assert "OPERATION Print-Job" in ipp_test
    assert "FILE $filename" in ipp_test
    assert "EXPECT job-id" in ipp_test


def test_document_is_timestamp_header_followed_by_nozzle_check_spool(fake):
    fake.run(PRINT_SCRIPT)
    document = (fake.capture / "document").read_bytes()

    header, sep, spool = document.partition(b"====================================================\n\n")
    assert sep, "header banner missing"
    assert re.search(rb"Test Page - Printed on: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", header)
    # Epson remote-mode spool data: EJL preamble and the nozzle-check ("NC") command.
    assert spool.startswith(b"\x00\x00\x00\x1b\x01@EJL")
    assert b"REMOTE1NC" in spool


def test_removes_temp_files_after_success(fake):
    before = _leftover_temp_files()
    assert fake.run(PRINT_SCRIPT).returncode == 0
    assert _leftover_temp_files() - before == set()


def test_propagates_ipptool_failure_and_still_cleans_up(fake):
    before = _leftover_temp_files()
    result = fake.run(PRINT_SCRIPT, FAKE_IPPTOOL_RC=3)
    assert result.returncode == 3
    assert "ipptool rc=3" in result.stderr
    assert _leftover_temp_files() - before == set()
