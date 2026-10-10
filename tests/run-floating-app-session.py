#!/usr/bin/env python3
"""Exercise production session races. App rendering/input still need a device."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-floating-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "floating-session")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(root / "tests/DXFloatingAppSessionTests.m"),
                    str(root / "DXFloatingAppSession.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
