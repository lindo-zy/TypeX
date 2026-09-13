#import "DXShared.h"

BOOL preferencesBool(NSString* key, BOOL fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value boolValue] : fallback;
}

float preferencesFloat(NSString* key, float fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value floatValue] : fallback;
}

int preferencesInt(NSString* key, int fallback) {
    NSNumber* value;
    if (prefs) value = prefs[key];
    return value ? [value intValue] : fallback;
}

NSString *preferencesSelectorForIdentifierScoped(NSString* identifier, int selectorNum, int gestureType, NSString *fallback, NSString *configuration) {
    //HBLogDebug(@"identifier: %@", identifier);
    //0-long press, 1-swipe up, 2-swipe down, 3-swipe left, 4-swipe right
    NSString *k = DXCustomActionsKeyForGesture(gestureType, configuration);
    
    NSString *selector = fallback;
    if (selectorNum == 1 && [prefs[k] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in prefs[k]) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:identifier]) continue;

            // Old two-action preferences stored the action that survives the UI
            // simplification as selector2.  Prefer it whenever the legacy key is
            // present (including an intentionally empty value).
            id storedSelector = entry[@"selector2"] ?: entry[@"selector"];
            if ([storedSelector isKindOfClass:[NSString class]]) selector = storedSelector;
            break;
        }
    }
    // Reject unknown selectors while still allowing supported legacy actions
    // that are intentionally hidden from the current picker.
    return [DXShortcutsGenerator isAvailableShortcutSelector:selector] ? selector : fallback;
}

NSString *preferencesSelectorForIdentifier(NSString* identifier, int selectorNum, int gestureType, NSString *fallback) {
    return preferencesSelectorForIdentifierScoped(identifier, selectorNum, gestureType, fallback, @"bottom");
}

// Ordered sub-actions configured for one button ("添加子动作" page). Each
// entry is {identifier, selector}; several entries may share an identifier and
// array order is the execution order. Hidden/legacy selectors are rejected so
// old or hand-edited plists cannot dispatch unknown actions.
NSArray<NSString *> *preferencesSubActionSelectorsForIdentifier(NSString* identifier, NSString *configuration) {
    NSMutableArray<NSString *> *selectors = [NSMutableArray array];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return selectors;
    if (![prefs[DXScopedPreferenceKey(kSubActionskey, configuration)] isKindOfClass:[NSArray class]]) return selectors;

    for (NSDictionary *entry in prefs[DXScopedPreferenceKey(kSubActionskey, configuration)]) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:identifier]) continue;
        NSString *selector = entry[@"selector"];
        if (![selector isKindOfClass:[NSString class]] || selector.length == 0) continue;
        if (![DXShortcutsGenerator isVisibleShortcutSelector:selector]) continue;
        [selectors addObject:selector];
    }
    return selectors;
}
