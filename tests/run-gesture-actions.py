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
capacity = common[common.index("static inline NSInteger DXMultiRowButtonsPerRowFromPreferences"):
                  common.index("// Fields whose text was set programmatically")]
numeric_defines = "\n".join(re.findall(r'^#define (?:buttonsPerRowDefault|maxMultiRowRows|maxEnabledTopButtons|maxMultiRowButtons|maxEnabledBottomButtons) .+$', common, re.M))
controller = (ROOT / "typexprefs/DXPCustomActionViewController.m").read_text()
cleanup = controller[controller.index("- (void)removeReferencesToSelector:"):
                     controller.index("#pragma mark - Action editor")]

with tempfile.TemporaryDirectory(prefix="typex-gesture-tests-") as tmp:
    tmp = pathlib.Path(tmp)
    (tmp / "GestureProduction.h").write_text(
        '#import <Foundation/Foundation.h>\n#import "DXKeyboardPanelPreferences.h"\n#import "DXToolbarGesturePolicy.h"\n#import "DXStatusBarGesturePolicy.h"\n' + defines + "\n" + numeric_defines + "\n" + scoped + capacity + gestures +
        '\n@interface GestureCleanup : NSObject\n'
        '- (void)removeReferencesToSelector:(NSString *)selector fromPreferences:(NSMutableDictionary *)preferences;\n'
        '@end\n@implementation GestureCleanup\n' + cleanup + '@end\n')
    binary = tmp / "gesture-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-function", "-framework", "Foundation", "-I", str(tmp), "-I", str(ROOT),
                    str(ROOT / "tests/DXGestureActionTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)

    geometry_binary = tmp / "keyboard-geometry-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-framework", "CoreGraphics", "-I", str(ROOT),
                    str(ROOT / "tests/DXKeyboardPanelGeometryTests.m"), "-o", str(geometry_binary)], check=True)
    subprocess.run([str(geometry_binary)], check=True, timeout=15)

    # Compile the actual UIKit recognizer against narrow view/event doubles.
    # UIKit's own event arbitration still needs a device check.
    (tmp / "UIKit").mkdir()
    (tmp / "UIKit/UIKit.h").write_text(r'''#import <Foundation/Foundation.h>
#import <math.h>
typedef NSPoint CGPoint;
typedef NSRect CGRect;
#define CGRectZero NSZeroRect
#define CGRectMake NSMakeRect
#define CGPointMake NSMakePoint
#define CGRectGetWidth NSWidth
#define CGRectContainsPoint(rect, point) NSPointInRect(point, rect)
@class UIWindow, UIEvent, UITouch;
@interface UIView : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic) CGRect bounds;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@interface UIWindow : UIView @end
@interface UIButton : UIView
@property(nonatomic, copy) NSString *accessibilityIdentifier;
@end
@interface UITouch : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
@interface UIEvent : NSObject
@property(nonatomic, copy) NSSet<UITouch *> *allTouches;
@end
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) {
    UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged,
    UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed
};
@interface UIGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic, weak) UIView *view;
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
- (void)reset;
@end
''')
    (tmp / "UIKit/UIGestureRecognizerSubclass.h").write_text('#import "UIKit.h"\n')
    recognizer_binary = tmp / "recognizer-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-I", str(tmp), "-I", str(ROOT),
                    str(ROOT / "DXToolbarHorizontalGesture.m"),
                    str(ROOT / "tests/DXToolbarHorizontalGestureTests.m"),
                    "-o", str(recognizer_binary)], check=True)
    subprocess.run([str(recognizer_binary)], check=True, timeout=15)
