#import "../DXPanelRegistry.h"
static inline NSArray *DXTestGesturePanels(void) {
    NSMutableArray *panels = [NSMutableArray array];
    for (NSString *identifier in @[@"test-left", @"test-right", @"test-common"])
        [panels addObject:@{@"id": identifier, @"kind": DXPanelGestureKind, @"name": identifier, @"items": @[]}];
    return panels;
}

static inline NSArray *DXTestMixedPanels(void) {
    return [DXTestGesturePanels() arrayByAddingObject:@{@"id": @"keyboard-only", @"kind": DXPanelKeyboardKind, @"name": @"Keyboard only", @"items": @[]}];
}
