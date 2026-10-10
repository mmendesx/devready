#!/usr/bin/env python3
"""Exercise the real Bash prompts in a terminal without running installation."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import termios
import time


ROOT = Path(__file__).resolve().parents[1]


def choose(keys, args=(), rows=24, columns=80):
    master, terminal = pty.openpty()
    fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
    original = termios.tcgetattr(terminal)
    process = subprocess.Popen(
        ["bash", "-c", 'source "$1"; shift; parse_args "$@" || exit $?; show_selection',
         "check-interactive", str(ROOT / "devready"), *args],
        stdin=terminal, stdout=terminal, stderr=terminal,
        env=dict(os.environ, TERM="xterm"),
    )
    output = bytearray()

    def receive_until(done):
        deadline = time.monotonic() + 5
        while not done():
            assert time.monotonic() < deadline, output.decode(errors="replace")
            if select.select([master], [], [], 0.05)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break

    try:
        if keys is not None:
            receive_until(lambda: b"Space" in output or b"Profile [" in output or process.poll() is not None)
            assert b"Profile [" not in output, "Setup must open the tool checklist without asking for a profile."
            assert b"Space" in output, "The tool checklist must offer Space to toggle."
            assert b"0 selected" in output, "Tools must start unchecked so the user chooses what to install."
            receive_until(lambda: not (termios.tcgetattr(terminal)[3] & termios.ICANON)
                          or process.poll() is not None)
            os.write(master, keys)
        receive_until(lambda: process.poll() is not None)
        while select.select([master], [], [], 0)[0]:
            output.extend(os.read(master, 65536))
        assert termios.tcgetattr(terminal) == original, "The checklist changed terminal settings."
        return process.returncode, output.decode(errors="replace")
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
        os.close(terminal)


def expect(keys, components, **options):
    status, output = choose(keys, **options)
    assert status == 0, output
    actual = re.search(r"^Components: (.+)\r?$", output, re.MULTILINE)
    assert actual and actual[1].strip() == components, output
    return output


expect(b" \x1b[B\x1b[B \n", "java,node")
expect(b" \x1b[B \x1b[A \n", "python")
expect(b"\x1b[1;2A \n", "java")  # Shift+Up must not select everything.
expect(b"\x1b[B" * 3 + b" \n", "go")
expect(b"\x1b[B" * 4 + b" \n", "c")
expect(b"\x1b[B" * 5 + b" \n", "cpp")
output = expect(b"\x1b[B" * 11 + b" \n", "codex,node")
assert "Node development tools: false" in output
output = expect(b"\n \n", "java")
assert "Select at least one tool" in output
expect(b"\x1b[B" * 14 + b" \n", "superpowers,node")
output = expect(b"a\n", "java,python,node,go,c,cpp,docker,tools,lsp,shell,codex,claude,laya,superpowers,ponytail,ui-taste",
                args=("--headless",))
assert "Headless: true" in output
expect(b"aa \n", "java")
expect(b" \n", "java,python", args=("--project", str(ROOT)))
expect(b"\x1b[B" * 13 + b" \n", "laya,python", rows=8)
output = expect(b"\x1b[A" * 5 + b" \n", "claude", rows=8, columns=40)
menu = output[output.index("Choose tools"):output.rindex("Components:")]
assert all(len(line) < 40 for line in re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", menu).splitlines()), output
for key in (b"q", b"\x1b", b"\x1b\n", b"\x04"):
    status, output = choose(key)
    assert status != 0 and "Selection cancelled" in output, output
    assert not re.search(r"^Components:", output, re.MULTILINE), output
output = expect(None, "fonts", args=("--components", "fonts", "--yes"))
assert "Space" not in output
expect(None, "tools", args=("--profile", "minimal", "--dry-run"))
expect(None, "ponytail,node", args=("--components", "ponytail", "--yes"))
print("Interactive checklist selection, navigation, cancellation, dependencies, and terminal restoration passed.")
