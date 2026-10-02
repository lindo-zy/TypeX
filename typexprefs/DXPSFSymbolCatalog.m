#import "DXPSFSymbolCatalog.h"

// The format adapters follow SFSymbolReplacer's local catalog reader.
// Only names are read here; no replacement hooks or built-in catalog is used.
static void DXPAppendSymbolName(id value, NSMutableOrderedSet<NSString *> *names) {
    if (![value isKindOfClass:NSString.class]) return;
    NSString *name = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length) [names addObject:name];
}

static void DXPCollectSymbolNames(id object, NSMutableOrderedSet<NSString *> *names, NSUInteger depth) {
    if (depth > 8) return;
    if ([object isKindOfClass:NSArray.class]) {
        for (id entry in object) {
            if ([entry isKindOfClass:NSString.class]) {
                DXPAppendSymbolName(entry, names);
            } else if ([entry isKindOfClass:NSDictionary.class]) {
                for (NSString *key in @[@"name", @"symbol", @"Name"]) {
                    id value = entry[key];
                    if ([value isKindOfClass:NSString.class] && [value length]) {
                        DXPAppendSymbolName(value, names);
                        break;
                    }
                }
            }
        }
    } else if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = object;
        // Wrapped catalogs contain metadata such as year_to_release alongside
        // symbols. Those metadata keys must not become candidate symbol names.
        if (dictionary[@"names"] || dictionary[@"symbols"]) {
            for (NSString *key in @[@"names", @"symbols"]) {
                id value = dictionary[key];
                if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) {
                    DXPCollectSymbolNames(value, names, depth + 1);
                }
            }
            return;
        }
        NSMutableArray<NSString *> *keys = [NSMutableArray array];
        for (id key in dictionary) {
            if ([key isKindOfClass:NSString.class] && ![key hasPrefix:@"CF"] &&
                ![key isEqualToString:@"version"] && ![key isEqualToString:@"year_to_release"]) {
                [keys addObject:key];
            }
        }
        [keys sortUsingSelector:@selector(compare:)];
        for (NSString *key in keys) DXPAppendSymbolName(key, names);
    }
}

@implementation DXPSFSymbolCatalog

+ (NSArray<NSString *> *)systemResourceDirectories {
    NSMutableOrderedSet<NSString *> *directories = [NSMutableOrderedSet orderedSet];
    for (NSString *resourceRoot in @[
        @"/System/Library/CoreServices/CoreGlyphs.bundle",
        @"/System/Library/PrivateFrameworks/CoreGlyphs.framework/CoreGlyphs.bundle",
        @"/System/Library/PrivateFrameworks/SFSymbols.framework",
    ]) {
        // System resources keep their real /System path on RootHide.
        [directories addObject:resourceRoot];
        [directories addObject:[resourceRoot stringByAppendingPathComponent:@"Resources"]];
        NSString *resolvedResources = [NSBundle bundleWithPath:resourceRoot].resourcePath;
        if (resolvedResources.length) [directories addObject:resolvedResources];
    }
    return directories.array;
}

+ (NSArray<NSString *> *)namesFromResourceDirectories:(NSArray<NSString *> *)directories
                                         sourcePaths:(NSArray<NSString *> **)sourcePaths {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *sources = [NSMutableOrderedSet orderedSet];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    // Preserve symbol_order order; availability adds names missing from it.
    for (NSString *fileName in @[@"symbol_order.plist", @"name_availability.plist"]) {
        for (NSString *directory in directories) {
            if (![directory isKindOfClass:NSString.class] || !directory.length) continue;
            NSString *path = [[directory stringByAppendingPathComponent:fileName] stringByStandardizingPath];
            if ([visited containsObject:path]) continue;
            [visited addObject:path];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data.length) continue;
            id object = [NSPropertyListSerialization propertyListWithData:data
                                                                  options:NSPropertyListImmutable
                                                                   format:NULL error:NULL];
            NSMutableOrderedSet<NSString *> *fileNames = [NSMutableOrderedSet orderedSet];
            DXPCollectSymbolNames(object, fileNames, 0);
            if (!fileNames.count) continue;
            [names addObjectsFromArray:fileNames.array];
            [sources addObject:path];
        }
    }
    if (sourcePaths) *sourcePaths = sources.array;
    // No failure cache: a later retry always reads disk again.
    return names.array;
}

@end
