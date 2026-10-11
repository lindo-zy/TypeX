// Narrow installed-app inventory/navigation doubles. The app controller and
// search predicates are production code; this does not emulate UIKit rendering.
typedef NS_ENUM(NSInteger, UITableViewCellEditingStyle) { UITableViewCellEditingStyleNone, UITableViewCellEditingStyleDelete };
@interface NSIndexPath (PanelApplications)
@property(nonatomic, readonly) NSInteger row, section;
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@end
@implementation NSIndexPath (PanelApplications)
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section {
    NSUInteger indexes[] = {(NSUInteger)section, (NSUInteger)row};
    return [self indexPathWithIndexes:indexes length:2];
}
- (NSInteger)row { return [self indexAtPosition:1]; }
- (NSInteger)section { return [self indexAtPosition:0]; }
@end
@interface ATLApplicationSection : NSObject
@property(nonatomic, copy) NSString *sectionName;
@end
@implementation ATLApplicationSection @end
@interface ATLApplicationListMultiSelectionController : PSListController {
@protected NSMutableArray *_allSpecifiers;
    NSString *_searchKey;
    UIImage *_placeholderAppIcon;
}
@property(nonatomic, copy) NSArray *availableSpecifiers;
@property(nonatomic, copy) NSString *searchKey;
@property(nonatomic) BOOL includeIdentifiersInSearch;
- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section;
- (NSString *)localizedStringForString:(NSString *)string;
- (Class)customCellClassForCellType:(PSCellType)cell;
- (BOOL)shouldHideApplicationSpecifiers;
- (BOOL)shouldHideApplicationSpecifier:(PSSpecifier *)specifier;
@end
@implementation ATLApplicationListMultiSelectionController
@synthesize searchKey = _searchKey;
- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section { return [PSSpecifier groupSpecifierWithName:section.sectionName]; }
- (NSString *)localizedStringForString:(NSString *)string { return string; }
- (Class)customCellClassForCellType:(PSCellType)cell { (void)cell; return nil; }
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        _allSpecifiers = [self.availableSpecifiers mutableCopy] ?: [NSMutableArray array];
        NSMutableArray *visible = [NSMutableArray array];
        for (PSSpecifier *row in _allSpecifiers.reverseObjectEnumerator) {
            if ([self shouldHideApplicationSpecifiers]) {
                if (row.cellType != PSGroupCell && [self shouldHideApplicationSpecifier:row]) continue;
                if (row.cellType == PSGroupCell && (!visible.count || [visible.firstObject cellType] == PSGroupCell)) continue;
            }
            [visible insertObject:row atIndex:0];
        }
        _specifiers = visible;
    }
    return (NSMutableArray *)_specifiers;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([[self specifierAtIndexPath:indexPath] propertyForKey:@"applicationIdentifier"]) cell.accessoryView = [NSObject new];
    return cell;
}
#include "PanelApplicationsSearch.inc"
@end
