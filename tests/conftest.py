"""Shared fixtures for exercising the Bash scripts without real hardware.

Every external command the scripts call (ipptool, systemctl, apt, curl,
timedatectl, sudo) is replaced by a small stub on PATH. Each stub appends its
argv to a log file so tests can assert exactly what would have run.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

BASH = shutil.which("bash") or "/bin/bash"

REPO_ROOT = Path(__file__).resolve().parent.parent
PRINT_SCRIPT = "self_contained_print_test_page.sh"
SETUP_SCRIPT = "setup_print_test_page.sh"
REPO_FILES = [PRINT_SCRIPT, SETUP_SCRIPT, "print_test_page.service", "print_test_page.timer"]

# Generic stub: log "<name> <args...>" and exit with $FAKE_<NAME>_RC (default 0).
_STUB = """#!/bin/bash
echo "{name} $*" >> "$FAKE_CMD_LOG"
rc_var="FAKE_{upper}_RC"
exit "${{!rc_var:-0}}"
"""

# ipptool stub also keeps a copy of the document (-f) and the IPP test file
# (last argument), since the script deletes both right after ipptool returns.
_IPPTOOL_STUB = """#!/bin/bash
echo "ipptool $*" >> "$FAKE_CMD_LOG"
prev=""
for arg in "$@"; do
    if [ "$prev" = "-f" ]; then cp "$arg" "$FAKE_CAPTURE_DIR/document"; fi
    prev="$arg"
done
cp "${@: -1}" "$FAKE_CAPTURE_DIR/ipp-test-file"
exit "${FAKE_IPPTOOL_RC:-0}"
"""

# curl stub prints $FAKE_CURL_OUTPUT (the "detected" timezone).
_CURL_STUB = """#!/bin/bash
echo "curl $*" >> "$FAKE_CMD_LOG"
printf '%s' "${FAKE_CURL_OUTPUT:-}"
"""

# sudo stub just runs the command, so run_as_root works when not root.
_SUDO_STUB = """#!/bin/bash
echo "sudo $*" >> "$FAKE_CMD_LOG"
exec "$@"
"""


class FakeSystem:
    """A working directory plus a PATH full of logging stubs."""

    def __init__(self, tmp_path: Path):
        self.workdir = tmp_path / "work"
        self.bin = tmp_path / "bin"
        self.capture = tmp_path / "capture"
        self.log = tmp_path / "commands.log"
        for d in (self.workdir, self.bin, self.capture):
            d.mkdir()
        self.log.touch()
        for name in REPO_FILES:
            shutil.copy2(REPO_ROOT / name, self.workdir / name)
        self.env_extra = {}

    def stub(self, name: str, body: str | None = None) -> None:
        path = self.bin / name
        if body is None:
            body = _STUB.format(name=name, upper=name.upper().replace("-", "_"))
        path.write_text(body)
        path.chmod(0o755)

    def stub_defaults(self, *, ipptool: bool = True) -> None:
        for name in ("systemctl", "apt", "timedatectl"):
            self.stub(name)
        self.stub("curl", _CURL_STUB)
        self.stub("sudo", _SUDO_STUB)
        if ipptool:
            self.stub("ipptool", _IPPTOOL_STUB)

    def commands(self) -> list[str]:
        return [line for line in self.log.read_text().splitlines() if line]

    def run(self, script: str, *args: str, **env) -> subprocess.CompletedProcess:
        full_env = {
            "PATH": f"{self.bin}:/usr/local/bin:/usr/bin:/bin",
            "HOME": os.environ.get("HOME", "/tmp"),
            "FAKE_CMD_LOG": str(self.log),
            "FAKE_CAPTURE_DIR": str(self.capture),
            **self.env_extra,
            **{k: str(v) for k, v in env.items()},
        }
        return subprocess.run(
            [BASH, str(self.workdir / script), *args],
            cwd=self.workdir,
            env=full_env,
            capture_output=True,
            text=True,
            timeout=60,
        )


@pytest.fixture
def fake(tmp_path) -> FakeSystem:
    system = FakeSystem(tmp_path)
    system.stub_defaults()
    return system
