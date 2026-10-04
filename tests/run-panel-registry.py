#!/usr/bin/env python3
"""Exercise production registry and reference cleanup on macOS/Foundation."""
import pathlib
import re
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[1]
common = (root / "common.h").read_text()
defines = "\n".join(re.findall(r'^#define \w+ @"[^"\n]*"$', common, re.M))
scoped = common[common.index("static inline NSString *DXScopedPreferenceKey"):common.index("static inline NSInteger DXMultiRowButtonsPerRowFromPreferences")]
gestures = common[common.index("typedef NS_ENUM(NSInteger, DXShortcutGestureType)"):common.index("static inline UIColor *DXColorFromHex")]
controller = (root / "typexprefs/DXPCustomActionViewController.m").read_text()
cleanup = controller[controller.index("- (void)removeReferencesToSelector:"):controller.index("#pragma mark - Action editor")]
with tempfile.TemporaryDirectory(prefix="typex-panel-registry-") as directory:
    tmp = pathlib.Path(directory)
    (tmp / "PanelRegistryProduction.h").write_text(
        '#import <Foundation/Foundation.h>\n#import "DXPanelRegistry.h"\n#import "DXDockGesturePolicy.h"\n#import "DXStatusBarGesturePolicy.h"\n'
        + defines + '\n' + scoped + gestures
        + '\n@interface PanelCleanup : NSObject\n- (void)removeReferencesToSelector:(NSString *)selector fromPreferences:(NSMutableDictionary *)preferences;\n@end\n@implementation PanelCleanup\n' + cleanup + '@end\n')
    binary = tmp / "panel-registry"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-framework", "Foundation", "-I", str(tmp), "-I", str(root), str(root / "tests/DXPanelRegistryTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
