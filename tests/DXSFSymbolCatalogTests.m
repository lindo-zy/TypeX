#import <Foundation/Foundation.h>
#import "../typexprefs/DXPSFSymbolCatalog.h"

static NSUInteger checks;
static void check(BOOL value) {
    NSCAssert(value, @"catalog check %lu failed", (unsigned long)checks + 1);
    checks++;
}

static void writePlist(id object, NSString *directory, NSString *fileName, NSPropertyListFormat format) {
    check([[NSFileManager defaultManager] createDirectoryAtPath:directory
        withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:object format:format options:0 error:NULL];
    check(data != nil);
    check([data writeToFile:[directory stringByAppendingPathComponent:fileName] atomically:YES]);
}

int main(void) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *first = [root stringByAppendingPathComponent:@"first"];
        NSString *second = [root stringByAppendingPathComponent:@"second"];
        NSArray<NSString *> *sources = nil;
        NSArray *names = [DXPSFSymbolCatalog namesFromResourceDirectories:@[first] sourcePaths:&sources];
        check(!names.count && !sources.count); // No built-in fallback or sticky failure cache.

        writePlist(@[@" doc ", @"heart", @"doc", @42, @"", @{@"name": @42, @"symbol": @"star"},
                     @{@"Name": @"gear"}, @{@"other": @"ignored"}], first, @"symbol_order.plist", NSPropertyListXMLFormat_v1_0);
        names = [DXPSFSymbolCatalog namesFromResourceDirectories:@[first] sourcePaths:&sources];
        check([names isEqual:@[@"doc", @"heart", @"star", @"gear"]]);
        check(sources.count == 1);

        writePlist(@{@"symbols": @{@"zebra": @"2021", @"heart": @"2019", @"alpha": @"2022"},
                     @"year_to_release": @{@"2022": @{@"iOS": @"16.0"}}, @"version": @3},
                   first, @"name_availability.plist", NSPropertyListBinaryFormat_v1_0);
        writePlist(@{@"names": @[@"later", @"doc"], @"symbols": @[@{@"symbol": @"last"}]},
                   second, @"symbol_order.plist", NSPropertyListBinaryFormat_v1_0);
        names = [DXPSFSymbolCatalog namesFromResourceDirectories:@[first, second, first] sourcePaths:&sources];
        check([names isEqual:@[@"doc", @"heart", @"star", @"gear", @"later", @"last", @"alpha", @"zebra"]]);
        check(sources.count == 3);
        check(![names containsObject:@"year_to_release"] && ![names containsObject:@"symbols"]);

        NSString *broken = [root stringByAppendingPathComponent:@"broken"];
        writePlist(@42, broken, @"name_availability.plist", NSPropertyListXMLFormat_v1_0);
        check([[@"invalid plist" dataUsingEncoding:NSUTF8StringEncoding]
               writeToFile:[broken stringByAppendingPathComponent:@"symbol_order.plist"] atomically:YES]);
        check(![DXPSFSymbolCatalog namesFromResourceDirectories:@[broken] sourcePaths:&sources].count);
        check(!sources.count);
        check([DXPSFSymbolCatalog namesFromResourceDirectories:@[broken, first] sourcePaths:NULL].count == 6);

        writePlist(@{@"symbols": @42, @"names": @42, @"year_to_release": @{}},
                   broken, @"symbol_order.plist", NSPropertyListXMLFormat_v1_0);
        check(![DXPSFSymbolCatalog namesFromResourceDirectories:@[broken] sourcePaths:NULL].count);
        writePlist(@{@"beta": @"2020", @"alpha": @"2019", @"CFBundleVersion": @"1", @"version": @1},
                   broken, @"symbol_order.plist", NSPropertyListXMLFormat_v1_0);
        check([[DXPSFSymbolCatalog namesFromResourceDirectories:@[broken] sourcePaths:NULL]
               isEqual:@[@"alpha", @"beta"]]);

        NSMutableArray *large = [NSMutableArray array];
        for (NSUInteger index = 0; index < 8000; index++) {
            [large addObject:[NSString stringWithFormat:@"fixture.%lu", (unsigned long)index]];
        }
        [large addObjectsFromArray:[large copy]];
        writePlist(large, broken, @"symbol_order.plist", NSPropertyListBinaryFormat_v1_0);
        names = [DXPSFSymbolCatalog namesFromResourceDirectories:@[broken] sourcePaths:NULL];
        check(names.count == 8000 && [names.lastObject isEqualToString:@"fixture.7999"]);

        // Exercise the actual macOS system resources when present. This tests
        // Foundation catalog parsing, not iOS UIImage rendering or Settings UI.
        NSArray *local = [DXPSFSymbolCatalog namesFromResourceDirectories:
            [DXPSFSymbolCatalog systemResourceDirectories] sourcePaths:&sources];
        if (sources.count) {
            check(local.count > 0 && [NSSet setWithArray:local].count == local.count);
            NSLog(@"Local macOS catalog: %lu names from %lu resources", (unsigned long)local.count, (unsigned long)sources.count);
        }
        check([[NSFileManager defaultManager] removeItemAtPath:root error:NULL]);
        NSLog(@"PASS: %lu local SF catalog checks", (unsigned long)checks);
    }
    return 0;
}
