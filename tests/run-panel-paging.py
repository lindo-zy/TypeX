#!/usr/bin/env python3
"""Test production page geometry and paging view; no iOS/device UI access."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-panel-paging-") as temp:
    temp = pathlib.Path(temp)
    flags = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
             "-framework", "Foundation", "-framework", "CoreGraphics"]
    geometry = temp / "geometry"
    subprocess.run(flags + [str(root / "tests/DXPanelPagingTests.m"), "-o", str(geometry)], check=True)
    subprocess.run([str(geometry)], check=True, timeout=15)
    (temp / "UIKit").mkdir()
    (temp / "UIKit/UIKit.h").write_bytes((root / "tests/UIKitPanelPagingStub.h").read_bytes())
    view = temp / "paging-view"
    subprocess.run(flags + ["-I", str(temp), str(root / "tests/DXPanelPagedGridViewTests.m"),
                           str(root / "DXPanelPagedGridView.m"), "-o", str(view)], check=True)
    subprocess.run([str(view)], check=True, timeout=15)
