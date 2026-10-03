#!/usr/bin/env python3
"""Exercise production policy. UIKit recognition/private hooks require device checks."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-statusbar-tests-") as temporary:
    binary = str(pathlib.Path(temporary) / "statusbar-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(root / "tests/DXStatusBarGestureTests.m"),
                    "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
