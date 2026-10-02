#import <Foundation/Foundation.h>
#include <math.h>

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

// Begin in the Dock's lower background, above the system Home gesture area.
static inline BOOL DXDockPanelOriginAllowed(double x, double y, double width, double height) {
    return isfinite(x) && isfinite(y) && isfinite(width) && isfinite(height) && width > 0 && height > 0 &&
        x >= 0 && x <= width && y >= fmax(0, height - 22) && y <= height;
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
