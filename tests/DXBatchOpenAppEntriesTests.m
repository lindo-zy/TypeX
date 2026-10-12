#import "DXBatchOpenAppEntries.h"
#import <Foundation/Foundation.h>

static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }

// Key defines and the helper are injected by tests/run-batch-apps.py; the
// helper is production code sliced out of DXPBatchOpenAppEntries.h.
int main(void) {
    @autoreleasepool {
        NSArray *apps = @[
            @{@"bundleID": @"com.a.b", @"name": @"A"},
            @{@"bundleID": @"com.c.d", @"name": @""},
            @{@"bundleID": @"com.e.f", @"name": @"E"},
        ];

        NSUInteger skipped = 99;
        NSArray *entries = DXBatchOpenAppEntries(@[], apps, &skipped);
        check(skipped == 0 && entries.count == 3, @"clean batch adds every pick in order");
        check([entries[0][@"link"] isEqual:@"com.a.b"] && [entries[0][@"icon"] isEqual:@"com.a.b"] &&
              [entries[0][@"name"] isEqual:@"A"] && [entries[0][@"type"] isEqual:@"openapp"] &&
              [entries[0][@"floating"] isEqual:@YES], @"entry mirrors the single-add defaults");
        check([entries[0][@"selector"] hasPrefix:@"__typex_link_action_"] &&
              ![entries[0][@"selector"] isEqual:entries[2][@"selector"]], @"selectors unique with action prefix");
        check([entries[1][@"name"] isEqual:@"com.c.d"], @"missing name falls back to the bundle ID");

        NSArray *existing = @[
            @{@"type": @"openapp", @"link": @"  com.a.b\n"},
            @{@"type": @"urlscheme", @"link": @"com.c.d"},
            @"junk",
        ];
        skipped = 0;
        entries = DXBatchOpenAppEntries(existing, apps, &skipped);
        check(skipped == 1 && entries.count == 2, @"existing openapp action blocks its app, link compared trimmed");
        check([entries[0][@"link"] isEqual:@"com.c.d"], @"a non-openapp entry with the same link does not block");
        check([entries[0][@"link"] isEqual:@"com.c.d"] && [entries[1][@"link"] isEqual:@"com.e.f"], @"remaining picks keep their order");

        skipped = 0;
        entries = DXBatchOpenAppEntries(@[], @[apps[0], apps[0], @{@"bundleID": @"com.a.b", @"name": @"A2"}], &skipped);
        check(skipped == 2 && entries.count == 1, @"batch-internal duplicates collapse into one entry");

        skipped = 0;
        entries = DXBatchOpenAppEntries(@[@"junk", @{}],
            @[@"junk", @{}, @{@"name": @"x"}, @{@"bundleID": @"", @"name": @"y"}], &skipped);
        check(entries.count == 0 && skipped == 4, @"malformed picks are skipped, never crash");

        entries = DXBatchOpenAppEntries(@[], apps, NULL);
        check(entries.count == 3, @"nil skipped counter is optional");
        NSMutableDictionary *first = entries[0];
        first[@"name"] = @"renamed";
        check([entries[0][@"name"] isEqual:@"renamed"], @"entries come back mutable for in-place editing");

        printf("PASS: %lu batch openapp entry checks\n", (unsigned long)checks);
    }
    return 0;
}
