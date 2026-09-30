#import <Foundation/Foundation.h>
#include <math.h>

#define kDXPanelTopEnabled @"keyboardpaneltopBOOL"
#define kDXPanelBottomEnabled @"keyboardpanelbottomBOOL"
#define kDXPanelUnified @"keyboardpanelunifiedBOOL"
#define kDXPanelColumns @"keyboardpanelcolumns"
#define kDXPanelScale @"keyboardpanelscale"
#define kDXPanelDark @"keyboardpaneldarkBOOL"
#define kDXPanelSliders @"keyboardpanelslidersBOOL"
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
    if (!stored) {
        NSArray *selectors = [side isEqualToString:@"right"]
            ? @[@"aiChatAction:", @"copyAction:", @"pasteAction:", @"undoAction:", @"redoAction:", @"deleteAllAction:"]
            : @[@"selectAllAction:", @"copyAction:", @"pasteAction:", @"cutAction:", @"undoAction:", @"dismissKeyboardAction:"];
        NSMutableArray *defaults = [NSMutableArray array];
        for (NSString *selector in selectors) [defaults addObject:@{@"id": selector, @"selector": selector}];
        return defaults;
    }
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
