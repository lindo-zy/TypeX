#pragma once
#import "../common.h"

// 自定义动作分组 helpers for the standalone management page. Groups are
// display-only metadata: each entry carries an optional kCustomActionGroupKey
// string and the ordered registry lives in kLinkActionGroupsKey. Nothing here
// feeds an execution path — the flat array stays the order every consumer
// sees, and all existing references (panels, toolbar, gestures, sub-actions)
// keep working. Foundation-only so the test runner compiles the slice
// directly.

static inline NSString *DXActionGroupNormalizedName(NSString *name) {
    NSString *trimmed = [name isKindOfClass:NSString.class]
        ? [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    return trimmed.length <= 32 ? trimmed : [trimmed substringToIndex:32];
}

// Validated registry: non-empty unique names, stored order preserved.
static inline NSArray<NSString *> *DXActionStoredGroups(NSDictionary *preferences) {
    id stored = preferences[kLinkActionGroupsKey];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    for (id name in stored) {
        NSString *normalized = DXActionGroupNormalizedName(name);
        if (!normalized.length || [groups containsObject:normalized]) continue;
        [groups addObject:normalized];
    }
    return groups;
}

// Members of one group in flat-array order; a nil/empty group collects
// entries without a usable kCustomActionGroupKey (the trailing 未分组 set).
static inline NSArray<NSDictionary *> *DXActionsInGroup(NSArray *actions, NSString *group) {
    NSString *target = DXActionGroupNormalizedName(group);
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *entry in actions) {
        NSString *member = DXActionGroupNormalizedName(entry[kCustomActionGroupKey]);
        if (target.length ? [member isEqualToString:target] : !member.length) [result addObject:entry];
    }
    return result;
}

// Section names: registry order first, then groups referenced by entries but
// missing from the registry, in first-appearance order. The trailing 未分组
// section is the caller's concern.
static inline NSArray<NSString *> *DXActionGroupNames(NSDictionary *preferences, NSArray *actions) {
    NSMutableArray<NSString *> *groups = [DXActionStoredGroups(preferences) mutableCopy];
    for (NSDictionary *entry in actions) {
        NSString *name = DXActionGroupNormalizedName(entry[kCustomActionGroupKey]);
        if (name.length && ![groups containsObject:name]) [groups addObject:name];
    }
    return groups;
}

// Assign or clear one action's group by selector (empty group clears the key;
// entries fall back to 未分组). Every matching entry updates — the registry has
// never enforced selector uniqueness. Returns whether anything changed.
static inline BOOL DXActionAssignGroup(NSMutableArray *actions, NSString *selector, NSString *group) {
    NSString *normalized = DXActionGroupNormalizedName(group);
    BOOL changed = NO;
    for (NSUInteger index = 0; index < actions.count; index++) {
        NSMutableDictionary *entry = actions[index];
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"selector"] isEqual:selector]) continue;
        if (normalized.length) {
            if (![entry[kCustomActionGroupKey] isEqual:normalized]) { entry[kCustomActionGroupKey] = normalized; changed = YES; }
        } else if (entry[kCustomActionGroupKey]) {
            [entry removeObjectForKey:kCustomActionGroupKey];
            changed = YES;
        }
    }
    return changed;
}

// Entries follow a registry rename; call after updating the stored array.
static inline void DXActionRenameGroup(NSMutableArray *actions, NSString *oldName, NSString *newName) {
    NSString *from = DXActionGroupNormalizedName(oldName), *to = DXActionGroupNormalizedName(newName);
    if (!from.length || !to.length || [from isEqualToString:to]) return;
    for (NSUInteger index = 0; index < actions.count; index++) {
        NSMutableDictionary *entry = actions[index];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if ([DXActionGroupNormalizedName(entry[kCustomActionGroupKey]) isEqualToString:from]) entry[kCustomActionGroupKey] = to;
    }
}

// A deleted group's members fall back to 未分组 (the key is simply removed).
static inline void DXActionUngroupMembers(NSMutableArray *actions, NSString *group) {
    NSString *name = DXActionGroupNormalizedName(group);
    if (!name.length) return;
    for (NSUInteger index = 0; index < actions.count; index++) {
        NSMutableDictionary *entry = actions[index];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if ([DXActionGroupNormalizedName(entry[kCustomActionGroupKey]) isEqualToString:name]) [entry removeObjectForKey:kCustomActionGroupKey];
    }
}

// Management-page search: matches name, link and the caller-provided type
// display name, case-insensitive. An empty query returns everything (the
// controller gates search mode on non-empty text).
static inline NSArray<NSDictionary *> *DXActionsMatchingQuery(NSArray *actions, NSString *query,
                                                              NSString *(^typeName)(NSDictionary *entry)) {
    NSString *needle = [query isKindOfClass:NSString.class]
        ? [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    if (!needle.length) return [actions copy];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *entry in actions) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
        NSString *link = [entry[@"link"] isKindOfClass:NSString.class] ? entry[@"link"] : @"";
        NSString *type = typeName ? (typeName(entry) ?: @"") : @"";
        if ([name localizedCaseInsensitiveContainsString:needle] ||
            [link localizedCaseInsensitiveContainsString:needle] ||
            ([type isKindOfClass:NSString.class] && [type localizedCaseInsensitiveContainsString:needle]))
            [result addObject:entry];
    }
    return result;
}
