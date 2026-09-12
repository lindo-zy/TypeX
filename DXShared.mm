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
    //0-long press
    NSString *k = DXScopedPreferenceKey(kCustomActionskey, configuration);
    
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
