#!/usr/bin/env python3
"""Exercise the production Foundation helpers. Does not invoke iOS system APIs."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-system-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "system-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", "-framework", "Foundation",
                    str(root / "tests/DXSystemActionTests.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
