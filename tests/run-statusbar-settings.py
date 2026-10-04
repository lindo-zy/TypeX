#!/usr/bin/env python3
"""Compile the production Settings controller against narrow Foundation doubles.

Exercises configured row actions, binding persistence and editor callbacks;
native Preferences dispatch and UIKit navigation still require iOS checks.
"""
import json
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
common = (root / "common.h").read_text()
defines = "\n".join(re.findall(r'^#define \w+ @"[^"\n]*"$', common, re.M))
scoped = common[common.index("static inline NSString *DXScopedPreferenceKey"):common.index("static inline NSInteger DXMultiRowButtonsPerRowFromPreferences")]
gestures = common[common.index("typedef NS_ENUM(NSInteger, DXShortcutGestureType)"):common.index("static inline UIColor *DXColorFromHex")]
source = (root / "typexprefs/DXPStatusBarGestureController.m").read_text()
source = re.sub(r'^#import .*\n', '', source, flags=re.M)
dock_source = re.sub(r'^#import .*\n', '', (root / "typexprefs/DXPDockGestureController.m").read_text(), flags=re.M)
toolbar = (root / "typexprefs/DXPGesturePickerController.mm").read_text()
summary = toolbar[toolbar.index("- (NSString *)readGestureActionSummary:"):toolbar.index("// All preference stores")]
canonical = toolbar[toolbar.index("- (NSDictionary *)canonicalEntryForSelector:"):toolbar.index("// After the tap action picker")]
toolbar_fixture = """
static NSBundle *tweakBundle;
@interface ToolbarGestureRecord : NSObject
@property(nonatomic) BOOL pendingNewEntry;
@property(nonatomic, copy) NSString *identifier, *configuration;
@property(nonatomic, copy) NSArray *fullOrder;
- (NSString *)readGestureActionSummary:(PSSpecifier *)specifier;
- (NSDictionary *)canonicalEntryForSelector:(NSString *)selector;
@end
#define LOCALIZED(key) [tweakBundle localizedStringForKey:key value:key table:nil]
@implementation ToolbarGestureRecord
+ (void)initialize { if (self == ToolbarGestureRecord.class) tweakBundle = [NSBundle bundleWithPath:bundlePath]; }
""" + summary + canonical + "@end\n"
subactions = (root / "typexprefs/DXPSubActionsController.m").read_text()
subaction_lookup = subactions[subactions.index("- (NSDictionary *)linkActionForSelector:"):subactions.index("- (UIImage *)displayImageForSelector:")]
subaction_fixture = """
@interface SubActionRecord : NSObject
- (NSDictionary *)linkActionForSelector:(NSString *)selector;
- (NSString *)displayNameForSelector:(NSString *)selector;
@end
@implementation SubActionRecord
""" + subaction_lookup + "@end\n"
with tempfile.TemporaryDirectory(prefix="typex-statusbar-settings-") as temporary:
    tmp = pathlib.Path(temporary)
    (tmp / "UIKit").mkdir()
    (tmp / "UIKit/UIKit.h").write_text('#import "PreferencesStatusBarStub.h"\n')
    (tmp / "StatusBarSettingsProduction.h").write_text(
        '#import "PreferencesStatusBarStub.h"\n#import "DXPanelRegistry.h"\n#import "DXStatusBarGesturePolicy.h"\n#import "DXGlobalPanelPolicy.h"\n#import "DXDockGesturePolicy.h"\n#import "DXPGestureActionCell.h"\n'
        + defines + '\n#define bundlePath @' + json.dumps(str(root / "typexprefs/Resources")) + '\n'
        + scoped + gestures + '\n' + source + '\n' + dock_source + '\n' + toolbar_fixture + subaction_fixture)
    binary = tmp / "statusbar-settings-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(root), "-I", str(root / "tests"), "-I", str(root / "typexprefs"),
                    str(root / "tests/DXStatusBarSettingsTests.m"), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
    if result.returncode:
        print(result.stderr)
    result.check_returncode()
    print(result.stdout, end="")
