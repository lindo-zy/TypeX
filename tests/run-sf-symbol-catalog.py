#!/usr/bin/env python3
"""Host Foundation tests for the production local SF catalog reader."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-sf-catalog-tests-") as tmp:
    binary = str(pathlib.Path(tmp) / "catalog-tests")
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
        "-framework", "Foundation", str(root / "tests/DXSFSymbolCatalogTests.m"),
        str(root / "typexprefs/DXPSFSymbolCatalog.m"), "-o", binary,
    ], check=True)
    subprocess.run([binary], check=True, timeout=15)
