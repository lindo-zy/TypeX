#import <Foundation/Foundation.h>
#include <math.h>

#define kDXPanelTopEnabled @"keyboardpaneltopBOOL"
#define kDXPanelBottomEnabled @"keyboardpanelbottomBOOL"
#define kDXPanelGlobalEnabled @"keyboardpanelglobalBOOL"
#define kDXPanelDockSwipeEnabled @"keyboardpaneldockswipeBOOL"
#define kDXPanelUnified @"keyboardpanelunifiedBOOL"
#define kDXPanelSystemTogglesVisible @"keyboardpanelsystemtogglesBOOL"
#define kDXPanelSystemSlidersVisible @"keyboardpanelsystemslidersBOOL"
#define kDXPanelColumns @"keyboardpanelcolumns"
#define kDXPanelScale @"keyboardpanelscale"
#define kDXPanelDark @"keyboardpaneldarkBOOL"
#define kDXPanelLeftItems @"keyboardpanelleftitems"
#define kDXPanelRightItems @"keyboardpanelrightitems"
#define kDXPanelCommonItems @"keyboardpanelcommonitems"

static inline NSString *DXKeyboardPanelItemsKey(NSString *side) {
    if ([side isEqualToString:@"right"]) return kDXPanelRightItems;
    if ([side isEqualToString:@"common"]) return kDXPanelCommonItems;
    return kDXPanelLeftItems;
}

static inline NSArray<NSDictionary *> *DXKeyboardPanelItems(NSDictionary *preferences, NSString *side) {
    if (![preferences isKindOfClass:NSDictionary.class]) return @[];
    id stored = preferences[DXKeyboardPanelItemsKey(side)];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *selector = entry[@"selector"];
        if (![selector isKindOfClass:NSString.class] || !selector.length) continue;
        NSMutableDictionary *item = [@{@"selector": selector} mutableCopy];
        for (NSString *field in @[@"id", @"name", @"icon"]) {
            if ([entry[field] isKindOfClass:NSString.class]) item[field] = entry[field];
        }
        [items addObject:item];
    }
    return items;
}

// Panel entries reference user-created definitions only. Never execute a
// built-in selector or a dangling definition imported from an older profile.
static inline NSArray<NSDictionary *> *DXKeyboardPanelFilterCustomItems(NSArray<NSDictionary *> *items,
                                                                        id definitions, NSString *prefix) {
    if (![definitions isKindOfClass:NSArray.class] || !prefix.length) return @[];
    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    for (id definition in definitions) {
        if (![definition isKindOfClass:NSDictionary.class]) continue;
        id selector = definition[@"selector"];
        if ([selector isKindOfClass:NSString.class] && [selector hasPrefix:prefix] && [selector length] > prefix.length)
            [allowed addObject:selector];
    }
    NSMutableArray *filtered = [NSMutableArray array];
    if (![items isKindOfClass:NSArray.class]) return @[];
    for (id item in items) if ([item isKindOfClass:NSDictionary.class] &&
        [item[@"selector"] isKindOfClass:NSString.class] && [allowed containsObject:item[@"selector"]]) [filtered addObject:item];
    return filtered;
}

static inline double DXKeyboardPanelNumber(NSDictionary *preferences, NSString *key,
                                         double fallback, double minimum, double maximum) {
    id value = preferences[key];
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    if (!isfinite(number)) number = fallback;
    return MIN(maximum, MAX(minimum, number));
}

static inline BOOL DXKeyboardPanelBool(NSDictionary *preferences, NSString *key, BOOL fallback) {
    id value = preferences[key];
    return value ? ([value isKindOfClass:NSNumber.class] && [value boolValue]) : fallback;
}
