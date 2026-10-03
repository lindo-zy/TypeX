#!/usr/bin/env python3
"""Production Dock gesture policy; real UIKit arbitration needs device checks."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-dock-gesture-tests-") as temporary:
    binary = str(pathlib.Path(temporary) / "dock-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(root / "tests/DXDockGestureTests.m"),
                    "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)
    temporary = pathlib.Path(temporary)
    (temporary / "UIKit").mkdir()
    (temporary / "UIKit/UIKit.h").write_bytes((root / "tests/UIKitDockGestureStub.h").read_bytes())
    hooks = (root / "DXGlobalPanelHooks.xm").read_text()
    body = hooks[hooks.index("@interface DXDockPanelGestureHandler"):hooks.index("%group TypeXGlobalDock")]
    (temporary / "DockHandler.inc").write_text(body)
    handler = temporary / "dock-handler-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-Wno-incomplete-implementation", "-framework", "Foundation", "-framework", "CoreGraphics",
                    "-I", str(temporary), "-I", str(root), "-I", str(root / "tests"),
                    str(root / "tests/DXDockGestureHandlerTests.m"), "-o", str(handler)], check=True)
    subprocess.run([str(handler)], check=True, timeout=15)
