#import "DXActionGroups.h"
#import <Foundation/Foundation.h>

static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }

// Key defines and the helpers are injected by tests/run-action-groups.py; the
// helpers are production code sliced out of typexprefs/DXPActionGroups.h.
static NSDictionary *entry(NSString *selector, NSString *name, NSString *group) {
    NSMutableDictionary *result = [@{@"selector": selector, @"name": name, @"type": @"openapp", @"link": selector} mutableCopy];
    if (group.length) result[@"group"] = group;
    return result;
}

int main(void) {
    @autoreleasepool {
        check([DXActionGroupNormalizedName(@"  a b \n") isEqual:@"a b"] &&
              [DXActionGroupNormalizedName(@"") isEqual:@""] && DXActionGroupNormalizedName(nil).length == 0 &&
              [DXActionGroupNormalizedName((NSString *)@42) isEqual:@""], @"normalizer trims and drops non-strings");
        NSString *longName = [@"abcdefghij" stringByAppendingString:@"0123456789abcdefghijklmno"]; // 35 chars
        check(DXActionGroupNormalizedName(longName).length == 32, @"long names cap at 32 characters");

        NSDictionary *prefs = @{kLinkActionGroupsKey: @[@"工作", @"  ", @"工作", @42, @"出行"]};
        check([DXActionStoredGroups(prefs) isEqual:@[@"工作", @"出行"]], @"stored registry validates, dedupes and keeps order");
        check(DXActionStoredGroups(@{}).count == 0, @"missing registry means no groups");

        NSArray *actions = @[entry(@"s1", @"A", @"工作"), entry(@"s2", @"B", @"  "), entry(@"s3", @"C", nil), entry(@"s4", @"D", @"出行")];
        check([DXActionsInGroup(actions, @"工作") isEqual:@[actions[0]]], @"group members resolve in array order");
        check([DXActionsInGroup(actions, nil) isEqual:@[actions[1], actions[2]]], @"blank-group entries collect as 未分组");
        check(DXActionsInGroup(actions, @"不存在").count == 0, @"unknown group is empty");

        check([DXActionGroupNames(@{}, actions) isEqual:@[@"工作", @"出行"]], @"discovered groups append in first-appearance order");
        check([DXActionGroupNames(prefs, actions) isEqual:@[@"工作", @"出行"]], @"registry order wins over discovery");
        check([DXActionGroupNames(@{}, @[]) isEqual:@[]], @"nothing stored and nothing discovered means no sections");

        NSMutableArray *mutable = [actions mutableCopy];
        check(!DXActionAssignGroup(mutable, @"missing", @"工作"), @"unknown selector changes nothing");
        check(DXActionAssignGroup(mutable, @"s3", @"工作") &&
              [mutable[2][kCustomActionGroupKey] isEqual:@"工作"], @"assign sets the group");
        check(DXActionAssignGroup(mutable, @"s1", @"") && mutable[0][kCustomActionGroupKey] == nil,
              @"blank group removes the key so the entry falls back to 未分组");
        mutable[0][kCustomActionGroupKey] = @"工作";
        [mutable addObject:entry(@"s1", @"A-dup", nil)];
        DXActionAssignGroup(mutable, @"s1", @"出行");
        check([mutable[0][kCustomActionGroupKey] isEqual:@"出行"] &&
              [mutable[4][kCustomActionGroupKey] isEqual:@"出行"], @"duplicate selectors all follow the assignment");

        // Fresh entries: the assign block above mutated the shared elements.
        mutable = [@[entry(@"s1", @"A", @"工作"), entry(@"s2", @"B", nil), entry(@"s3", @"C", nil), entry(@"s4", @"D", @"出行")] mutableCopy];
        DXActionRenameGroup(mutable, @"工作", @"  深度工作  ");
        check([mutable[0][kCustomActionGroupKey] isEqual:@"深度工作"], @"rename rewrites member entries normalized");
        DXActionRenameGroup(mutable, @"工作", @"深度工作");
        check([mutable[0][kCustomActionGroupKey] isEqual:@"深度工作"], @"renaming away from a stale name is a no-op");
        DXActionRenameGroup(mutable, @"出行", @"");
        check([mutable[3][kCustomActionGroupKey] isEqual:@"出行"], @"empty target name changes nothing");

        DXActionUngroupMembers(mutable, @"深度工作");
        check(DXActionsInGroup(mutable, nil).count == 3 && DXActionsInGroup(mutable, @"出行").count == 1,
              @"deleted group falls back to 未分组, others untouched");

        NSString *(^rawType)(NSDictionary *) = ^NSString *(NSDictionary *dict) { return dict[@"type"]; };
        check(DXActionsMatchingQuery(actions, @"", rawType).count == 4, @"empty query passes everything through");
        check(DXActionsMatchingQuery(actions, @"  ", rawType).count == 4, @"whitespace-only query passes everything through");
        check([DXActionsMatchingQuery(actions, @"c", rawType) isEqual:@[actions[2]]], @"name search is case-insensitive");
        check(DXActionsMatchingQuery(actions, @"OPENAPP", rawType).count == 4, @"type display name participates");
        check([DXActionsMatchingQuery(actions, @"s4", rawType) isEqual:@[actions[3]]], @"link participates");
        check(DXActionsMatchingQuery(@[@"junk", @{}], @"a", rawType).count == 0, @"malformed entries never match or crash");

        // Section index map: the table's safety contract — buckets = groups+1,
        // every flat index appears exactly once, buckets keep array order.
        // Fresh entries again: the assign block above mutated shared elements.
        NSArray *placed = @[entry(@"s1", @"A", @"工作"), entry(@"s2", @"B", @"  "),
                            entry(@"s3", @"C", nil), entry(@"s4", @"D", @"出行")];
        NSArray<NSString *> *names = DXActionGroupNames(@{}, placed);
        NSArray<NSArray<NSNumber *> *> *sections = DXActionGroupSectionIndexes(placed, names);
        check(sections.count == names.count + 1, @"one bucket per group plus the trailing 未分组 bucket");
        NSMutableSet *seen = [NSMutableSet set];
        BOOL ordered = YES;
        for (NSArray *bucket in sections) {
            NSUInteger previous = 0;
            for (NSNumber *value in bucket) {
                if (value.unsignedIntegerValue < previous) ordered = NO;
                previous = value.unsignedIntegerValue;
                [seen addObject:value];
            }
        }
        check(ordered && seen.count == placed.count &&
              [seen isEqualToSet:[NSSet setWithArray:@[@0, @1, @2, @3]]],
              @"every flat index maps exactly once and in ascending order");
        check([sections[0] isEqual:@[@0]] && [sections[1] isEqual:@[@3]] && [sections[2] isEqual:@[@1, @2]],
              @"grouped and ungrouped buckets hold the right positions");
        check(DXActionGroupSectionIndexes(@[], @[]).count == 1, @"empty state still yields the 未分组 bucket");

        NSMutableDictionary *registry = [@{@"linkactions": [@[
            [@{@"selector": @"a", @"name": @"Alpha", @"type": @"openapp", @"group": @"Work"} mutableCopy],
            [@{@"selector": @"b", @"name": @"Beta", @"type": @"text", @"group": @"Work"} mutableCopy],
            [@{@"selector": @"c", @"name": @"Other", @"link": @"HTTPS://example.com"} mutableCopy]
        ] mutableCopy], kLinkActionGroupsKey: @[@"Work", @"Empty"], kLinkActionCollapsedGroupsKey: @[@"Work"]} mutableCopy];
        NSArray *defs = registry[@"linkactions"];
        check([DXActionFilteredIndexes(defs, @"work", @"openapp", nil) isEqual:@[@0]], @"group query and type filter intersect");
        check([DXActionDisplayType(defs[2]) isEqual:@"url"], @"legacy web links remain filterable");
        NSArray *rows = DXActionPickerRows(defs, registry, @"", @"", nil, YES);
        check([rows[0][@"kind"] isEqual:@"group"] && [rows[0][@"collapsed"] boolValue], @"picker respects persisted collapse state");
        check([rows.lastObject[@"kind"] isEqual:@"add"], @"picker add row remains accessible");
        check(DXActionPickerRows(defs, registry, @"alpha", @"", nil, NO).count == 1, @"search reveals collapsed actions");
        NSArray *order = [defs valueForKey:@"selector"];
        check(DXActionMoveSelectors(registry, [NSSet setWithObjects:@"a", @"gone", nil], @"Empty") == 1, @"batch move ignores a missing selector");
        check([[registry[@"linkactions"] valueForKey:@"selector"] isEqual:order], @"grouping keeps definition order");
        check(DXActionChangeGroup(registry, @"Work", @"Renamed"), @"group rename succeeds");
        check([DXActionCollapsedGroups(registry) containsObject:@"Renamed"], @"rename preserves collapsed state");
        check(DXActionChangeGroup(registry, @"Renamed", @""), @"group removal succeeds");
        check([registry[@"linkactions"] count] == 3 && !registry[@"linkactions"][1][@"group"], @"group removal preserves definitions");
        check([DXActionValidatedDraftGroup(registry, @"Renamed", @[]) isEqual:@""], @"removed draft group does not resurrect");
        check([DXActionValidatedDraftGroup(registry, @"New", @[@"New"]) isEqual:@"New"], @"new draft group is accepted only when explicitly created");
        check(DXActionMoveSelectors(registry, [NSSet setWithObject:@"a"], @"Missing") == 0, @"stale destination group is rejected");
        registry[@"linkactions"] = @[@42, @{@"selector": @"valid", @"group": @"Discovered"}];
        check([DXActionGroupNames(registry, DXActionMutableDefinitions(registry)) containsObject:@"Discovered"], @"group discovery tolerates malformed definitions");

        printf("PASS: %lu custom-action group checks\n", (unsigned long)checks);
    }
    return 0;
}
