#import "StatusBarSettingsProduction.h"

static NSUInteger checks;
static void check(BOOL condition) { checks++; NSCAssert(condition, @"Status-bar Settings check %lu", (unsigned long)checks); }
static PSSpecifier *rowForAction(PSListController *controller, SEL callback, NSString *selector) {
    for (PSSpecifier *row in controller.specifiers)
        if (row->action == callback && (!selector || [[row propertyForKey:@"actionSelector"] isEqual:selector])) return row;
    return nil;
}
static void click(PSSpecifier *row) {
    check(row && row->action && [row.target respondsToSelector:row->action]);
    PSListController *controller = row.target;
    NSInteger section = -1, rowIndex = -1;
    for (PSSpecifier *item in controller.specifiers) {
        if (item.cellType == PSGroupCell) { section++; rowIndex = -1; }
        else rowIndex++;
        if (item != row) continue;
        NSUInteger indexes[] = {(NSUInteger)section, (NSUInteger)rowIndex};
        NSIndexPath *path = [NSIndexPath indexPathWithIndexes:indexes length:2];
        UITableView *table = [UITableView new];
        [controller tableView:table didSelectRowAtIndexPath:path];
        check(table.deselections == 1);
        return;
    }
    check(NO);
}
static DXPStatusBarActionPicker *pickerForSlot(NSString *slot) {
    DXPStatusBarActionPicker *picker = [DXPStatusBarActionPicker new];
    // Exercise a specifier assigned after view loading, not a cached slot.
    [picker viewDidLoad];
    picker.specifier = [PSSpecifier new]; [picker.specifier setProperty:slot forKey:@"statusBarSlot"];
    picker.navigationController = [UINavigationController new];
    picker.navigationController.viewControllers = @[[PSViewController new], picker];
    [picker viewWillAppear:NO];
    return picker;
}
int main(void) {
    @autoreleasepool {
        DXPrefsManager *manager = DXPrefsManager.sharedInstance;
        NSString *custom = [kLinkActionSelectorPrefix stringByAppendingString:@"open"];
        NSString *panel = @"__typex_statusbar_panel_left";
        NSDictionary *definition = @{@"selector": custom, @"name": @"Safari", @"type": @"openapp", @"link": @"com.apple.mobilesafari"};
        NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
        for (NSString *region in DXStatusBarRegions()) for (NSString *gesture in DXStatusBarGestures())
            bindings[DXStatusBarSlot(region, gesture)] = @{@"enabled": @NO, @"selector": @"original"};
        NSDictionary *baseline = @{kDXStatusBarBindings: bindings, kLinkActionskey: @[definition,
            @{@"selector": [kLinkActionSelectorPrefix stringByAppendingString:@"text"], @"type": @"text", @"link": @"private"}], @"unrelated": @42};

        DXPStatusBarGestureController *root = [DXPStatusBarGestureController new];
        NSUInteger slots = 0;
        for (PSSpecifier *row in root.specifiers) if ([row propertyForKey:@"statusBarSlot"]) { check(DXStatusSlotValid([row propertyForKey:@"statusBarSlot"])); slots++; }
        check(slots == 15);
        for (NSString *slot in bindings) for (NSString *selector in @[panel, custom]) {
            manager.preferences = baseline;
            DXPStatusBarActionPicker *picker = pickerForSlot(slot);
            check(picker.specifiers.count == 7); // 2 groups + 3 panels + supported custom + Add.
            click(rowForAction(picker, @selector(selectAction:), selector));
            check([DXStatusBarBinding(manager.preferences, slot)[@"selector"] isEqual:selector]);
            check([DXStatusBarBinding(manager.preferences, slot)[@"enabled"] isEqual:@NO]);
            check(picker.navigationController.pops == 1);
            check([manager.preferences[@"unrelated"] isEqual:@42]);
            for (NSString *other in bindings) if (![other isEqual:slot]) check([DXStatusBarBinding(manager.preferences, other) isEqual:bindings[other]]);

            DXPStatusBarGestureEntryController *entry = [DXPStatusBarGestureEntryController new];
            entry.specifier = picker.specifier;
            click(rowForAction(entry, @selector(clearAction:), nil));
            check(!DXStatusBarBinding(manager.preferences, slot)[@"selector"]);
            check([DXStatusBarBinding(manager.preferences, slot)[@"enabled"] isEqual:@NO]);
            check([[entry readActionName:entry.specifier] isEqual:DXStatusLocalized(@"STATUS_BAR_UNASSIGNED")]);
        }

        manager.preferences = baseline;
        for (NSString *slot in @[@"", @"left.invalid", @"outside.tap"]) {
            DXPStatusBarActionPicker *picker = pickerForSlot(slot);
            NSUInteger writes = manager.writes;
            click(rowForAction(picker, @selector(selectAction:), panel));
            check(manager.writes == writes && picker.navigationController.pops == 0);
        }
        DXPStatusBarActionPicker *picker = pickerForSlot(@"left.tap");
        manager.ignoreWrites = YES;
        click(rowForAction(picker, @selector(selectAction:), panel));
        check(picker.navigationController.pops == 0);
        manager.ignoreWrites = NO;
        PSSpecifier *deleted = rowForAction(picker, @selector(selectAction:), custom);
        manager.preferences = @{kDXStatusBarBindings: bindings};
        NSUInteger writes = manager.writes;
        click(deleted);
        check(manager.writes == writes && picker.navigationController.pops == 0);

        manager.preferences = baseline;
        picker = pickerForSlot(@"middle.doubletap");
        click(rowForAction(picker, @selector(addAction:), nil));
        UIAlertController *alert = picker.presentedViewController;
        check(alert.actions.count == 5);
        UIAlertAction *cancel = alert.actions.lastObject;
        check(!cancel.handler && [manager.preferences isEqual:baseline]);
        UIAlertAction *system = alert.actions[3]; system.handler(system);
        DXPLinkActionEditorController *editor = picker.navigationController.topViewController;
        check([editor isKindOfClass:DXPLinkActionEditorController.class]);
        NSMutableDictionary *newDefinition = [editor.entry mutableCopy]; newDefinition[@"systemaction"] = @"play-pause";
        editor.completion(newDefinition);
        check(picker.selectAfterSave);
        check([DXStatusBarBinding(manager.preferences, @"middle.doubletap")[@"selector"] isEqual:newDefinition[@"selector"]]);
        writes = manager.writes; editor.completion(newDefinition);
        check(manager.writes == writes);
        [picker.navigationController popViewControllerAnimated:NO];
        [picker viewDidAppear:NO];
        check(!picker.selectAfterSave && picker.navigationController.pops == 2);
        [picker viewDidAppear:NO]; check(picker.navigationController.pops == 2);

        for (BOOL changedSlot = NO; ; changedSlot = YES) {
            manager.preferences = baseline;
            picker = pickerForSlot(@"right.longpress"); [picker addType:kCustomActionTypeSystem];
            editor = picker.navigationController.topViewController;
            newDefinition = [editor.entry mutableCopy]; newDefinition[@"systemaction"] = @"play-pause";
            if (changedSlot) [picker.specifier setProperty:@"left.tap" forKey:@"statusBarSlot"];
            else [picker.navigationController popViewControllerAnimated:NO];
            writes = manager.writes; editor.completion(newDefinition);
            check(manager.writes == writes && !picker.selectAfterSave && [manager.preferences isEqual:baseline]);
            if (changedSlot) break;
        }
        printf("PASS: %lu production status-bar Settings row-action, persistence, isolation and lifecycle checks (Preferences/UI doubles)\n", (unsigned long)checks);
    }
    return 0;
}
