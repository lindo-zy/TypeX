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

static DXPSFSymbolCategory *categoryForIdentifier(NSArray<DXPSFSymbolCategory *> *categories, NSString *identifier) {
    for (DXPSFSymbolCategory *category in categories) {
        if ([category.identifier isEqualToString:identifier]) return category;
    }
    return nil;
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

        NSArray *available = @[@"doc", @"heart", @"star", @"gear", @"later", @"last", @"alpha", @"zebra"];
        NSArray<DXPSFSymbolCategory *> *categories = [DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first]
            availableNames:available sourcePaths:&sources];
        check(categories.count == 1 && [categories.firstObject.identifier isEqualToString:@"all"]);
        check([categories.firstObject.symbolNames isEqual:available] && !categories.firstObject.iconName && !sources.count);
        check(![DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first] availableNames:@[] sourcePaths:NULL].count);
        writePlist(@[@{@"key": @"all", @"icon": @"square.grid.2x2", @"title": @"All Metadata"},
                     @{@"key": @"weather", @"icon": @"cloud.sun"}, @{@"key": @"variable"},
                     @{@"key": @"multicolor"}, @{@"key": @"communication", @"icon": @"message"},
                     @{@"key": @"empty"}, @{@"key": @"whatsnew"}, @{@"key": @42}],
                   first, @"categories.plist", NSPropertyListXMLFormat_v1_0);
        writePlist(@{@"doc": @[@"communication", @"multicolor", @"communication"],
                     @"heart": @[@"weather", @"communication", @"variable"], @"star": @[@"multicolor", @"whatsnew"],
                     @"gear": @42, @"last": @{@"categories": @[@"variable"]}, @"zebra": @[@"futurecategory"],
                     @"not.available": @[@"weather"]}, first, @"symbol_categories.plist", NSPropertyListBinaryFormat_v1_0);
        categories = [DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first, first]
            availableNames:available sourcePaths:&sources];
        check([[categories valueForKey:@"identifier"] isEqual:@[@"all", @"multicolor", @"variable", @"weather", @"communication", @"futurecategory", @"whatsnew"]]);
        check(sources.count == 2);
        check([categories.firstObject.title isEqualToString:@"All Metadata"]);
        check([categories.firstObject.iconName isEqualToString:@"square.grid.2x2"]);
        check([categoryForIdentifier(categories, @"communication").symbolNames isEqual:@[@"doc", @"heart"]]);
        check([categoryForIdentifier(categories, @"multicolor").symbolNames isEqual:@[@"doc", @"star"]]);
        check([categoryForIdentifier(categories, @"variable").symbolNames isEqual:@[@"heart", @"last"]]);
        check([categoryForIdentifier(categories, @"weather").symbolNames isEqual:@[@"heart"]]);
        check(!categoryForIdentifier(categories, @"empty"));

        writePlist(@{@"categories": @[@{@"key": @"communication", @"icon": @"other"}]},
                   second, @"categories.plist", NSPropertyListBinaryFormat_v1_0);
        writePlist(@{@"symbols": @{@"doc": @[@"weather", @"communication"]}},
                   second, @"symbol_categories.plist", NSPropertyListXMLFormat_v1_0);
        categories = [DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first, second]
            availableNames:available sourcePaths:NULL];
        check([categoryForIdentifier(categories, @"communication").iconName isEqualToString:@"message"]);
        check([categoryForIdentifier(categories, @"weather").symbolNames isEqual:@[@"doc", @"heart"]]);
        check(categoryForIdentifier(categories, @"communication").symbolNames.count == 2);
        check([[DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first] availableNames:@[@"heart", @"heart"]
            sourcePaths:NULL].firstObject.symbolNames isEqual:@[@"heart"]]);

        check([[@"invalid category plist" dataUsingEncoding:NSUTF8StringEncoding]
            writeToFile:[first stringByAppendingPathComponent:@"categories.plist"] atomically:YES]);
        categories = [DXPSFSymbolCatalog categoriesFromResourceDirectories:@[first] availableNames:available sourcePaths:NULL];
        check(categories.count == 7); // Readable membership stays usable without category definitions.
        check(!categoryForIdentifier(categories, @"weather").iconName);
        check([categoryForIdentifier(categories, @"weather").symbolNames isEqual:@[@"heart"]]);

        // Exercise the actual macOS system resources when present. This tests
        // Foundation catalog parsing, not iOS UIImage rendering or Settings UI.
        NSArray *local = [DXPSFSymbolCatalog namesFromResourceDirectories:
            [DXPSFSymbolCatalog systemResourceDirectories] sourcePaths:&sources];
        if (sources.count) {
            check(local.count > 0 && [NSSet setWithArray:local].count == local.count);
            NSLog(@"Local macOS catalog: %lu names from %lu resources", (unsigned long)local.count, (unsigned long)sources.count);
            NSArray<DXPSFSymbolCategory *> *localCategories = [DXPSFSymbolCatalog categoriesFromResourceDirectories:
                [DXPSFSymbolCatalog systemResourceDirectories] availableNames:local sourcePaths:&sources];
            if (sources.count) {
                check(localCategories.count > 1 && [localCategories.firstObject.symbolNames isEqual:local]);
                NSSet *allowed = [NSSet setWithArray:local];
                for (DXPSFSymbolCategory *category in localCategories) {
                    check(category.symbolNames.count > 0 && [[NSSet setWithArray:category.symbolNames] isSubsetOfSet:allowed]);
                }
                NSLog(@"Local macOS categories: %lu", (unsigned long)localCategories.count);
            }
        }
        check([[NSFileManager defaultManager] removeItemAtPath:root error:NULL]);
        NSLog(@"PASS: %lu local SF catalog checks", (unsigned long)checks);
    }
    return 0;
}
