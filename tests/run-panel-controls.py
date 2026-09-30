#!/usr/bin/env python3
"""Production model/session tests; no device or system setting is changed."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-panel-controls-") as tmp:
    binary = str(pathlib.Path(tmp) / "panel-controls")
    source = (root / "DXSystemOpenBroker.m").read_text()
    (pathlib.Path(tmp) / "panel-request-under-test.h").write_text(source[source.index("@interface DXPanelControlOperation"):])
    subprocess.run(["xcrun", "clang", "-I", tmp, "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics",
                    str(root / "tests/DXPanelControlTests.m"), str(root / "DXPanelControlSession.m"), "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=10)
