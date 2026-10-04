#!/usr/bin/env python3
"""Exercise production policy. UIKit recognition/private hooks require device checks."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="typex-statusbar-tests-") as temporary:
    binary = str(pathlib.Path(temporary) / "statusbar-tests")
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", str(root / "tests/DXStatusBarGestureTests.m"),
                    "-o", binary], check=True)
    subprocess.run([binary], check=True, timeout=15)

    tmp = pathlib.Path(temporary)
    (tmp / "UIKit").mkdir()
    (tmp / "UIKit/UIKit.h").write_text('#import "UIKitStatusBarGestureStub.h"\n')
    hooks = (root / "DXStatusBarGestureHooks.xm").read_text()
    handler = hooks[hooks.index("static char DXStatusHandlerKey"):hooks.index("%group TypeXStatusBarWrapper")]
    handler = handler.replace("static void DXTryStatusHooks(void);\n", "")
    (tmp / "StatusHandler.inc").write_text(handler)
    installer = hooks[hooks.index("static void DXTryStatusHooks(void) {"):hooks.index("void DXStartStatusBarGestures(void)")]
    # Execute the production runtime guards/retry decisions with a recording
    # substitute for Logos registration; actual injection remains device-only.
    installer = re.sub(r'%init\((\w+),\s*\w+\s*=\s*(\w+)\)', r'DXTestInstallHook(@"\1", \2)', installer)
    (tmp / "StatusHookInstaller.inc").write_text(installer)
    doubles = (root / "tests/DXDockGestureHandlerTests.m").read_text()
    (tmp / "StatusDoubles.inc").write_text(doubles[doubles.index("@implementation UIView\n"):doubles.index("static char DXDockPanelHandlerKey")])
    broker = (root / "DXSystemOpenBroker.m").read_text()
    (tmp / "StatusBroker.inc").write_text(broker[broker.index("static void DXPerformSystemOpen("):broker.index('    if ([kind isEqual:@"panel-control"])')] + '    reply(DXSystemOpenInvalid);\n}\n')
    (tmp / "StatusSender.inc").write_text(broker[broker.index("void DXRequestStatusBarGesture("):broker.index("void DXOpenSystemApplication(")])
    for name, frameworks in [("DXStatusBarGestureHandlerTests", ["CoreGraphics"]), ("DXStatusBarBrokerTests", [])]:
        test = tmp / name
        command = ["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-incomplete-implementation", "-framework", "Foundation", "-I", str(tmp), "-I", str(root), "-I", str(root / "tests")]
        for framework in frameworks:
            command.extend(["-framework", framework])
        subprocess.run(command + [str(root / "tests" / (name + ".m")), "-o", str(test)], check=True)
        result = subprocess.run([str(test)], capture_output=True, text=True, timeout=15)
        if result.returncode:
            print(result.stderr)
        result.check_returncode()
        print(result.stdout, end="")
