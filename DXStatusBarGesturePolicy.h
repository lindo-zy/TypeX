#import <Foundation/Foundation.h>
#include <math.h>

#define kDXStatusBarEnabled @"statusbargesturesBOOL"
#define kDXStatusBarLandscape @"statusbargesturesLandscapeBOOL"
#define kDXStatusBarBindings @"statusbargesturebindings"

static inline NSArray<NSString *> *DXStatusBarRegions(void) { return @[@"left", @"middle", @"right"]; }
static inline NSArray<NSString *> *DXStatusBarGestures(void) { return @[@"tap", @"doubletap", @"longpress", @"leftswipe", @"rightswipe"]; }
static inline NSString *DXStatusBarSlot(NSString *region, NSString *gesture) {
    if (![region isKindOfClass:NSString.class] || ![gesture isKindOfClass:NSString.class]) return nil;
    if (![DXStatusBarRegions() containsObject:region] || ![DXStatusBarGestures() containsObject:gesture]) return nil;
    return [NSString stringWithFormat:@"%@.%@", region, gesture];
}
static inline BOOL DXStatusBarFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
static inline NSDictionary *DXStatusBarBinding(NSDictionary *preferences, NSString *slot) {
    if (![preferences isKindOfClass:NSDictionary.class]) return @{};
    id bindings = preferences[kDXStatusBarBindings];
    id value = [bindings isKindOfClass:NSDictionary.class] && slot.length ? bindings[slot] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static inline NSString *DXStatusBarSelector(NSDictionary *preferences, NSString *slot) {
    NSDictionary *entry = DXStatusBarBinding(preferences, slot);
    id selector = entry[@"selector"];
    return DXStatusBarFlag(entry[@"enabled"]) && [selector isKindOfClass:NSString.class] && [selector length] ? selector : nil;
}
// Coordinates are local to the actual status-bar view, never to a fixed screen strip.
static inline NSString *DXStatusBarRegion(double x, double y, double width, double height) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        width <= 0 || height <= 0 || x < 0 || x >= width || y < 0 || y >= height) return nil;
    return x < width / 3 ? @"left" : (x < width * 2 / 3 ? @"middle" : @"right");
}
static inline NSString *DXStatusBarPanelSide(NSString *selector) {
    if (![selector isKindOfClass:NSString.class]) return nil;
    for (NSString *side in @[@"left", @"right", @"common"])
        if ([selector isEqual:[@"__typex_statusbar_panel_" stringByAppendingString:side]]) return side;
    return nil;
}
static inline void DXStatusBarRemoveActionReferences(NSMutableDictionary *preferences, NSString *selector) {
    id stored = preferences[kDXStatusBarBindings];
    if (![stored isKindOfClass:NSDictionary.class] || !selector.length) return;
    NSMutableDictionary *bindings = [stored mutableCopy];
    for (NSString *slot in [bindings.allKeys copy]) {
        id value = bindings[slot];
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"selector"] isEqual:selector]) continue;
        NSMutableDictionary *entry = [value mutableCopy];
        [entry removeObjectForKey:@"selector"];
        entry[@"enabled"] = @NO;
        bindings[slot] = entry;
    }
    preferences[kDXStatusBarBindings] = bindings;
}
