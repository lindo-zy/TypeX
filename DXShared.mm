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

NSDictionary *preferencesLinkActionForSelector(NSString *selector) {
    if (!DXIsLinkActionSelector(selector)) return nil;
    id stored = prefs[kLinkActionskey];
    if (![stored isKindOfClass:[NSArray class]]) return nil;
    for (NSDictionary *entry in (NSArray *)stored) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"selector"] isEqual:selector]) {
            return entry;
        }
    }
    return nil;
}

BOOL preferencesIsConfiguredActionSelector(NSString *selector) {
    return [DXShortcutsGenerator isVisibleShortcutSelector:selector] ||
           preferencesLinkActionForSelector(selector) != nil;
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
    return ([DXShortcutsGenerator isAvailableShortcutSelector:selector] ||
            preferencesLinkActionForSelector(selector) != nil) ? selector : fallback;
}

NSString *preferencesSelectorForIdentifier(NSString* identifier, int selectorNum, int gestureType, NSString *fallback) {
    return preferencesSelectorForIdentifierScoped(identifier, selectorNum, gestureType, fallback, @"bottom");
}

// Whether the "点按触发子动作" switch is on for one button. The flag is a
// field on the button's own shortcut entry (both the enabled and disabled
// sections are searched) so it follows the entry everywhere its identifier
// does, exactly like the name/icon overrides.
BOOL preferencesTapRunsSubActionsForIdentifier(NSString *identifier, NSString *configuration) {
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return NO;
    id stored = prefs[DXScopedPreferenceKey(kShortcutskey, configuration)];
    if (![stored isKindOfClass:[NSArray class]]) return NO;

    for (NSArray *section in (NSArray *)stored) {
        if (![section isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *entry in section) {
            if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"selector"] isEqual:identifier]) {
                return [entry[kTapSubActionsEntryKey] boolValue];
            }
        }
    }
    return NO;
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
        if (!preferencesIsConfiguredActionSelector(selector)) continue;
        [selectors addObject:selector];
    }
    return selectors;
}
