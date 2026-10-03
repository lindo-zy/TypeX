#import <Foundation/Foundation.h>
#include <math.h>
#import "DXSystemActionCatalog.h"

// New independent entrypoints. Existing keyboard/script protocols are untouched.
#define DXGlobalPanelLeftNotification @"com.lindo.typex/panel-left"
#define DXGlobalPanelRightNotification @"com.lindo.typex/panel-right"
#define DXGlobalPanelCommonNotification @"com.lindo.typex/panel-common"

static inline NSString *DXGlobalPanelString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static inline NSString *DXGlobalPanelNormalizedPayload(id value) {
    NSString *payload = [DXGlobalPanelString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [payload.lowercaseString hasPrefix:@"www."] ? [@"https://" stringByAppendingString:payload] : payload;
}

static inline NSString *DXGlobalPanelSideForNotification(NSString *name) {
    if ([name isEqual:DXGlobalPanelLeftNotification]) return @"left";
    if ([name isEqual:DXGlobalPanelRightNotification]) return @"right";
    if ([name isEqual:DXGlobalPanelCommonNotification]) return @"common";
    return nil;
}

// Accept the full Dock background, including gaps at icon height, plus the
// strip below it. Visible icon images are excluded by the touch-view policy.
static inline BOOL DXDockPanelOriginAllowed(double x, double y, double width, double height, double below) {
    return isfinite(x) && isfinite(y) && isfinite(width) && isfinite(height) && isfinite(below) &&
        width > 0 && height > 0 && below >= 0 && x >= 0 && x <= width &&
        y >= 0 && y <= height + below;
}
static inline BOOL DXDockPanelSwipeCompletes(double dx, double dy) {
    return isfinite(dx) && isfinite(dy) && dy <= -48 && -dy >= fabs(dx) * 1.5;
}

// SpringBoard cannot address another process's editor. Never silently replace
// its text parameter with an empty string or execute against a stale responder.
static inline BOOL DXGlobalPanelActionNeedsInput(NSDictionary *entry) {
    NSString *type = [entry[@"type"] isKindOfClass:NSString.class] ? entry[@"type"] : @"";
    NSString *link = [entry[@"link"] isKindOfClass:NSString.class] ? entry[@"link"] : @"";
    return [type isEqual:@"text"] || [type isEqual:@"javascript"] || [link containsString:@"@@@"];
}

static inline BOOL DXGlobalCustomActionSupported(id entry) {
    if (![entry isKindOfClass:NSDictionary.class] || DXGlobalPanelActionNeedsInput(entry)) return NO;
    NSString *type = DXGlobalPanelString(entry[@"type"]);
    if ([type isEqual:@"system"]) return DXSystemActionDefinition(entry[@"systemaction"]) != nil;
    NSString *payload = DXGlobalPanelNormalizedPayload(entry[@"link"]);
    if (!payload.length) return NO;
    if ([type isEqual:@"shortcut"]) return [DXGlobalPanelString(entry[@"shortcuttype"]) length] > 0;
    return !type.length || [@[@"openapp", @"urlscheme", @"url"] containsObject:type];
}
