#!/usr/bin/env python3
"""Exercise actual Foundation-only gesture logic on macOS; no device access."""
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
common = (ROOT / "common.h").read_text()
# Extract the production helpers without importing UIKit/RootHide on macOS.
defines = "\n".join(re.findall(r'^#define \w+ @"[^"\n]*"$', common, re.M))
scoped = common[common.index("static inline NSString *DXScopedPreferenceKey"):
                common.index("static inline NSInteger DXMultiRowButtonsPerRowFromPreferences")]
gestures = common[common.index("typedef NS_ENUM(NSInteger, DXShortcutGestureType)"):
                  common.index("static inline UIColor *DXColorFromHex")]
controller = (ROOT / "typexprefs/DXPCustomActionViewController.m").read_text()
cleanup = controller[controller.index("- (void)removeReferencesToSelector:"):
                     controller.index("#pragma mark - Action editor")]

with tempfile.TemporaryDirectory(prefix="typex-gesture-tests-") as tmp:
    tmp = pathlib.Path(tmp)
    (tmp / "GestureProduction.h").write_text(
        '#import <Foundation/Foundation.h>\n' + defines + "\n" + scoped + gestures +
        '\n@interface GestureCleanup : NSObject\n'
        '- (void)removeReferencesToSelector:(NSString *)selector fromPreferences:(NSMutableDictionary *)preferences;\n'
        '@end\n@implementation GestureCleanup\n' + cleanup + '@end\n')
    binary = tmp / "gesture-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-function", "-framework", "Foundation", "-I", str(tmp),
                    str(ROOT / "tests/DXGestureActionTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
