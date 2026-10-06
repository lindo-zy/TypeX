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
    # Compile the actual icon/background policy against narrow view doubles.
    # UIKit hit testing, private-class availability and pan arbitration remain
    # device-only checks; expanded icon padding is reproduced deterministically.
    tmp = pathlib.Path(tmp)
    (tmp / "UIKit").mkdir()
    (tmp / "UIKit/UIKit.h").write_bytes((root / "tests/UIKitDockTouchStub.h").read_bytes())
    touch_binary = tmp / "dock-touch-policy"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics", "-I", str(tmp), "-I", str(root),
                    str(root / "tests/DXDockPanelTouchTests.m"), "-o", str(touch_binary)], check=True)
    subprocess.run([str(touch_binary)], check=True, timeout=15)
    (tmp / "UIKit/UIKit.h").write_bytes((root / "tests/UIKitDockGestureStub.h").read_bytes())
    panel = (root / "DXGlobalPanel.m").read_text()
    (tmp / "GlobalForeground.inc").write_text(panel[panel.index("static BOOL DXGlobalPanelHasForegroundApplication"):panel.index("@implementation DXGlobalPanel\n")])
    (tmp / "GlobalInterruptions.inc").write_text(panel[panel.index("- (void)interrupted:"):panel.index("- (NSDictionary *)definition:")])
    lifecycle = tmp / "global-panel-lifecycle"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-Wno-incomplete-implementation", "-framework", "Foundation", "-framework", "CoreGraphics",
                    "-I", str(tmp), "-I", str(root), "-I", str(root / "tests"),
                    str(root / "tests/DXGlobalPanelLifecycleTests.m"), "-o", str(lifecycle)], check=True)
    subprocess.run([str(lifecycle)], check=True, timeout=15)
