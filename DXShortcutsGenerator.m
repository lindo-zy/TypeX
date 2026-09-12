#import "common.h"
#import "DXShortcutsGenerator.h"

static const NSBundle *tweakBundle;

@implementation DXShortcutsGenerator

+(BOOL)isAvailableShortcutSelector:(NSString *)selector {
    if (![selector isKindOfClass:[NSString class]]) return NO;
    static NSSet *selectors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selectors = [NSSet setWithArray:[[self sharedInstance] selectorNames]];
    });
    return [selectors containsObject:selector];
}

+(BOOL)isVisibleShortcutSelector:(NSString *)selector {
    if (![self isAvailableShortcutSelector:selector]) return NO;

    // These actions remain executable for existing preferences, but stay out of
    // the shortcut/action picker for new configurations.
    static NSSet *legacyHiddenSelectors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        legacyHiddenSelectors = [NSSet setWithArray:@[@"runCommandAction:", @"spongebobAction:"]];
    });
    return ![legacyHiddenSelectors containsObject:selector];
}

+(void)load{
    @autoreleasepool {
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        
        if (args.count != 0) {
            NSString *executablePath = args[0];
            
            if (executablePath) {
                NSString *processName = [executablePath lastPathComponent];
                
                BOOL isSpringBoard = [processName isEqualToString:@"SpringBoard"];
                BOOL isApplication = [executablePath rangeOfString:@"/Application"].location != NSNotFound;
                
                if (isSpringBoard || isApplication) {
                    tweakBundle = [NSBundle bundleWithPath:bundlePath];
                    [tweakBundle load];
                    [DXShortcutsGenerator sharedInstance];
                    
                }
            }
        }
    }
}

+(instancetype)sharedInstance{
    static dispatch_once_t predicate;
    static DXShortcutsGenerator *generator;
    dispatch_once(&predicate, ^{ generator = [[self alloc] init]; });
    return generator;
}

-(instancetype)init{
    self = [super init];
    if (self) {
        // TypeX only exposes its built-in keyboard actions.
    }
    return self;
}

-(NSArray *)imageNameArrayForiOS:(NSInteger)iosVersion{
    // 0 = iOS 12
    // 1 = iOS 13+
    NSArray *array;
    if (iosVersion == 0){
        array = @[@"UIButtonBarListIcon",@"UIButtonBarKeyboardCopy",@"UIButtonBarKeyboardPaste",@"UIButtonBarKeyboardCut",@"UIButtonBarKeyboardUndo",@"UIButtonBarKeyboardRedo", @"UIButtonBarKeyboardItalic", @"UIButtonBarArrowLeft", @"UIButtonBarArrowRight", @"delete_portrait", @"bold_dismiss_landscape", @"Black_BreadcrumbArrowLeft", @"Black_BreadcrumbArrowRight", @"KeyGlyph-upArrow-large", @"KeyGlyph-downArrow-large", @"UITabBarSearchTemplate", @"KeyGlyph-command-large", @"UICalloutBarPreviousArrow", @"UICalloutBarNextArrow", @"KeyGlyph-rtlTab-large", @"KeyGlyph-tab-large", @"KeyGlyph-return-large", @"KeyGlyph-rtlReturn-large", @"UIMovieScrubberEditingGlassLeft", @"UIMovieScrubberEditingGlassRight", @"UIRemoveControlMinusStroke", @"UITableGrabber", @"UIButtonBarListIcon", @"delete_portrait", @"bold_emoji_activity", @"delete_portrait", @"UITabBarSearchTemplate"];
    }else{
        array = @[@"doc.text",@"doc.on.doc",@"doc.on.clipboard",@"scissors",@"arrow.uturn.left.circle",@"arrow.uturn.right.circle", @"text.cursor", @"chevron.left.circle", @"chevron.right.circle", @"delete.left", @"keyboard.chevron.compact.down", @"arrowtriangle.left.circle.fill", @"arrowtriangle.right.circle.fill", @"arrowtriangle.up.circle.fill", @"arrowtriangle.down.circle.fill", @"doc.text.magnifyingglass", @"command", @"arrow.left.circle.fill", @"arrow.right.circle.fill", @"arrow.left.to.line", @"arrow.right.to.line", @"text.insert", @"text.append", @"decrease.quotelevel", @"increase.quotelevel", @"line.horizontal.3", @"paragraph", @"list.bullet", @"delete.right", @"circle.grid.3x3", @"delete.left", @"link.badge.plus"];
    }
    return array;
}

-(NSArray *)selectorNames{
    return @[@"selectAllAction:",@"copyAction:",@"pasteAction:",@"cutAction:",@"undoAction:",@"redoAction:", @"selectAction:", @"beginningAction:", @"endingAction:", @"deleteAction:", @"dismissKeyboardAction:", @"moveCursorLeftAction:", @"moveCursorRightAction:", @"moveCursorUpAction:", @"moveCursorDownAction:", @"defineAction:", @"runCommandAction:", @"moveCursorPreviousWordAction:", @"moveCursorNextWordAction:", @"moveCursorStartOfLineAction:", @"moveCursorEndOfLineAction:", @"moveCursorStartOfParagraphAction:", @"moveCursorEndOfParagraphAction:", @"moveCursorStartOfSentenceAction:", @"moveCursorEndOfSentenceAction:", @"selectLineAction:", @"selectParagraphAction:", @"selectSentenceAction:", @"deleteForwardAction:", @"spongebobAction:", @"deleteAllAction:", @"openLinkAction:"];
}

-(NSArray *)labelName{
    NSArray *array = @[LOCALIZED(@"LONG_SELECT_ALL"), LOCALIZED(@"LONG_COPY"), LOCALIZED(@"LONG_PASTE"), LOCALIZED(@"LONG_CUT"), LOCALIZED(@"LONG_UNDO"), LOCALIZED(@"LONG_REDO"), LOCALIZED(@"LONG_SELECT"), LOCALIZED(@"LONG_BEGINNING"), LOCALIZED(@"LONG_ENDING"), LOCALIZED(@"LONG_DELETE"), LOCALIZED(@"LONG_DISMISS_KEYBOARD"), LOCALIZED(@"LONG_MOVE_CURSOR_LEFT"), LOCALIZED(@"LONG_MOVE_CURSOR_RIGHT"), LOCALIZED(@"LONG_MOVE_CURSOR_UP"), LOCALIZED(@"LONG_MOVE_CURSOR_DOWN"), LOCALIZED(@"LONG_DEFINE"), LOCALIZED(@"LONG_RUN_COMMAND"), LOCALIZED(@"LONG_MOVE_CURSOR_PREVIOUS_WORD"), LOCALIZED(@"LONG_MOVE_CURSOR_NEXT_WORD"), LOCALIZED(@"LONG_MOVE_CURSOR_START_OF_LINE"), LOCALIZED(@"LONG_MOVE_CURSOR_END_OF_LINE"), LOCALIZED(@"LONG_MOVE_CURSOR_START_OF_PARAGRAPH"), LOCALIZED(@"LONG_MOVE_CURSOR_END_OF_PARAGRAPH"), LOCALIZED(@"LONG_MOVE_CURSOR_START_OF_SENTENCE"), LOCALIZED(@"LONG_MOVE_CURSOR_END_OF_SENTENCE"), LOCALIZED(@"LONG_SELECT_LINE"), LOCALIZED(@"LONG_SELECT_PARAGRAPH"),LOCALIZED(@"LONG_SELECT_SENTENCE"), LOCALIZED(@"LONG_DELETE_FORWARD"), LOCALIZED(@"LONG_SPONGEBOB"), LOCALIZED(@"LONG_DELETE_ALL"), LOCALIZED(@"LONG_OPEN_LINK")];
    return array;
}

-(NSArray *)shortenedlabelName{
    NSArray *array = @[LOCALIZED(@"SHORT_SELECT_ALL"), LOCALIZED(@"SHORT_COPY"), LOCALIZED(@"SHORT_PASTE"), LOCALIZED(@"SHORT_CUT"), LOCALIZED(@"SHORT_UNDO"), LOCALIZED(@"SHORT_REDO"), LOCALIZED(@"SHORT_SELECT"), LOCALIZED(@"SHORT_BEGINNING"), LOCALIZED(@"SHORT_ENDING"), LOCALIZED(@"SHORT_DELETE"), LOCALIZED(@"SHORT_DISMISS_KEYBOARD"), LOCALIZED(@"SHORT_MOVE_CURSOR_LEFT"), LOCALIZED(@"SHORT_MOVE_CURSOR_RIGHT"), LOCALIZED(@"SHORT_MOVE_CURSOR_UP"), LOCALIZED(@"SHORT_MOVE_CURSOR_DOWN"), LOCALIZED(@"SHORT_DEFINE"), LOCALIZED(@"SHORT_RUN_COMMAND"), LOCALIZED(@"SHORT_MOVE_CURSOR_PREVIOUS_WORD"), LOCALIZED(@"SHORT_MOVE_CURSOR_NEXT_WORD"), LOCALIZED(@"SHORT_MOVE_CURSOR_START_OF_LINE"), LOCALIZED(@"SHORT_MOVE_CURSOR_END_OF_LINE"), LOCALIZED(@"SHORT_MOVE_CURSOR_START_OF_PARAGRAPH"), LOCALIZED(@"SHORT_MOVE_CURSOR_END_OF_PARAGRAPH"), LOCALIZED(@"SHORT_MOVE_CURSOR_START_OF_SENTENCE"), LOCALIZED(@"SHORT_MOVE_CURSOR_END_OF_SENTENCE"), LOCALIZED(@"SHORT_SELECT_LINE"), LOCALIZED(@"SHORT_SELECT_PARAGRAPH"), LOCALIZED(@"SHORT_SELECT_SENTENCE"), LOCALIZED(@"SHORT_DELETE_FORWARD"), LOCALIZED(@"SHORT_SPONGEBOB"), LOCALIZED(@"SHORT_DELETE_ALL"), LOCALIZED(@"SHORT_OPEN_LINK")];
    return array;
}


@end
