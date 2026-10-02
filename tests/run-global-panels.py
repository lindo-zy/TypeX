#!/usr/bin/env python3
"""Production Dock eligibility and standalone geometry; no iOS system calls."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-global-panel-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "global-panels")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics",
                    str(root / "tests/DXGlobalPanelTests.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
