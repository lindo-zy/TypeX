#!/usr/bin/env python3
"""Host integration tests. Does not connect to or alter an iOS device."""
import pathlib
import selectors
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-open-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "channel-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(ROOT / "tests/DXDarwinOpenChannelTests.m"), "-o", binary], check=True)
    for mode in ["wire", "oversize", "absent"]:
        subprocess.run([binary, mode], check=True, timeout=15)
    server = subprocess.Popen([binary, "server"], stdout=subprocess.PIPE, text=True)
    try:
        selector = selectors.DefaultSelector()
        selector.register(server.stdout, selectors.EVENT_READ)
        assert selector.select(5), "server did not start"
        assert server.stdout.readline().strip() == "READY"
        for _ in range(3):
            subprocess.run([binary, "send"], check=True, timeout=15)
        subprocess.run([binary, "send-quick"], check=True, timeout=15)
        server.terminate()
        output, _ = server.communicate(timeout=5)
        assert output.count("EXEC ") == 4, output
    finally:
        if server.poll() is None:
            server.terminate()
            server.wait(timeout=5)
    blocked = subprocess.Popen([binary, "server-blocked"], stdout=subprocess.PIPE, text=True)
    try:
        selector = selectors.DefaultSelector()
        selector.register(blocked.stdout, selectors.EVENT_READ)
        assert selector.select(5), "blocked server did not start"
        assert blocked.stdout.readline().strip() == "READY"
        subprocess.run([binary, "expired"], check=True, timeout=15)
        blocked.terminate()
        output, _ = blocked.communicate(timeout=5)
        assert "EXEC " not in output, "expired request executed"
    finally:
        if blocked.poll() is None:
            blocked.terminate()
            blocked.wait(timeout=5)
    silent = subprocess.Popen([binary, "server-silent-reply"], stdout=subprocess.PIPE, text=True)
    try:
        selector = selectors.DefaultSelector()
        selector.register(silent.stdout, selectors.EVENT_READ)
        assert selector.select(5), "silent-reply server did not start"
        assert silent.stdout.readline().strip() == "READY"
        subprocess.run([binary, "send"], check=True, timeout=15)
        silent.terminate()
        output, _ = silent.communicate(timeout=5)
        assert output.count("EXEC ") == 1, output
    finally:
        if silent.poll() is None:
            silent.terminate()
            silent.wait(timeout=5)
    print("PASS: cross-process payload/reply, replay, duplicate replies, bounds, corruption, expiry, timeout, lost reply notification and cleanup")
