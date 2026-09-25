#!/usr/bin/env python3
"""Exercise production scheduling with a blocking RPC stand-in; no iOS device."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-sensitive-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "sensitive-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(root / "DXSensitiveURLExecutor.m"),
                    str(root / "tests/DXSensitiveURLExecutorTests.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
