#!/usr/bin/env python3
"""Production geometry and close method with process/UI doubles; no device claims."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "DXFloatingAppRuntime.mm").read_text()
with tempfile.TemporaryDirectory(prefix="typex-floating-runtime-") as tmp:
    tmp = pathlib.Path(tmp)
    (tmp / "UIKit").mkdir()
    (tmp / "UIKit/UIKit.h").write_bytes((root / "tests/UIKitFloatingInputStub.h").read_bytes())
    # Compile the real termination flow; intercept the POSIX signal in the fixture.
    (tmp / "FloatingClose.inc").write_text(source[source.index("- (void)close {"):source.index("- (void)minimize {")])
    (tmp / "FloatingObjectHelpers.inc").write_text(source[source.index("static id DXFloatObject("):source.index("static NSInteger DXFloatInteger(")])
    (tmp / "FloatingSceneMatch.inc").write_text(source[source.index("static BOOL DXFloatSceneMatches("):source.index("static id DXFloatFindScene(")])
    (tmp / "FloatingSwitcher.inc").write_text(source[source.index("static BOOL DXFloatRegisterSwitcherCard("):source.index("@implementation DXFloatingAppCoordinator")])
    (tmp / "FloatingRelay.inc").write_text(source[source.index("- (void)receivePinchWord:(uint64_t)word nonce:(uint32_t)nonce {"):source.index("- (void)stopInputRelay {")])
    (tmp / "FloatingBackdrop.inc").write_text(source[source.index("static BOOL DXFloatConfigureBackdropHitTesting("):source.index("@interface DXFloatingAppWindow")])
    for name, extra in [("Geometry", ["-framework", "CoreGraphics"]),
                        ("Close", [str(root / "DXFloatingAppSession.m"), "-I", str(tmp)]),
                        ("Input", ["-framework", "CoreGraphics", "-I", str(tmp)]),
                        ("Switcher", ["-I", str(tmp)]),
                        ("Relay", ["-framework", "CoreGraphics", "-I", str(tmp)]),
                        ("Backdrop", ["-framework", "QuartzCore", "-framework", "CoreGraphics", "-I", str(tmp)])]:
        binary = tmp / name
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                        "-framework", "Foundation", str(root / f"tests/DXFloatingApp{name}Tests.m"),
                        *extra, "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=15)
