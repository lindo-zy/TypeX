#import "DXCell.h"
#import "DXShortcutsGenerator.h"
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, direction) {
    Down = 0, DownRight = 1,
    Right = 2, UpRight = 3,
    Up = 4, UpLeft = 5,
    Left = 6, DownLeft = 7
};

@interface DXCollectionView : UICollectionView <UICollectionViewDataSource, UICollectionViewDelegate>
- (instancetype)initWithConfiguration:(NSString *)configuration;
@property (nonatomic, copy) NSString *configuration;
@property (nonatomic, assign, readonly) BOOL shortcutConfigurationAvailable;
@property (strong, nonatomic) NSArray *shortcuts;
// selector -> custom display name, resolved from the shortcut dictionaries;
// empty when no shortcut carries an override.
@property (strong, nonatomic) NSDictionary *customNames;
@property (nonatomic, assign) NSInteger hapticType;

@property (nonatomic, assign) BOOL refreshView;
@property (nonatomic, assign) BOOL firstCellVisible;
@property (nonatomic, assign) BOOL firstInit;
@property (nonatomic, strong) dispatch_block_t retestDispatchBlock;
@property (nonatomic, strong) dispatch_block_t autoPaginationDispatchBlock;
@property (nonatomic, assign) NSTimer *cursorTimer;
@property (nonatomic, assign) NSTimer *cursorTimerRetest;
@property (nonatomic, assign) NSInteger cursorMovingFactor;
@property (nonatomic, assign) float cursorTimerSpeed;
@property (nonatomic, assign) float t;
@property (strong, nonatomic) NSArray *indexArray;
@property (strong, nonatomic) NSArray *sectionOffsetForwardArray;
@property (strong, nonatomic) NSArray *sectionOffsetBackwardArray;

@property (nonatomic, assign) BOOL moveCursorWithSelect;
@property (nonatomic, assign) BOOL isWordSender;
@property (strong, nonatomic) DXShortcutsGenerator *shortcutsGenerator;

// Per-toolbar button chrome. Every value is read from the configuration-
// scoped preference key ("top"-prefixed for the top toolbar), so the two
// toolbars can be styled independently.
@property (nonatomic, assign) CGFloat buttonHeight;
@property (nonatomic, assign) CGFloat buttonRadius;
@property (nonatomic, assign) CGFloat buttonSpacing;
@property (nonatomic, assign) BOOL borderEnabled;
@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, assign) CGFloat widthScale;

-(void)reloadButtonChrome;
- (BOOL)buttonChromeActive;

/// Rebuilds the active shortcut/keyboard-type data from the current preference domain.
/// iOS 17 keeps the collection view alive while Settings writes preferences, so
/// invalidating only the on-disk cache is not sufficient.
-(void)reloadShortcutConfiguration;

-(void)shakeButton:(UIButton *)sender;
-(void)shakeView:(UIView *)sender;
-(IBAction)selectAllAction:(UIButton*)sender;
-(IBAction)copyAction:(UIButton*)sender;
-(IBAction)pasteAction:(UIButton*)sender;
-(IBAction)cutAction:(UIButton*)sender;
-(IBAction)undoAction:(UIButton*)sender;
-(IBAction)redoAction:(UIButton*)sender;
-(IBAction)selectAction:(UIButton*)sender;
-(IBAction)beginningAction:(UIButton*)sender;
-(IBAction)endingAction:(UIButton*)sender;
-(IBAction)deleteAction:(UIButton*)sender;
-(IBAction)deleteAllAction:(UIButton*)sender;
-(IBAction)openLinkAction:(UIButton*)sender;
-(IBAction)dismissKeyboardAction:(UIButton*)sender;
-(void)moveCursorLeftAction:(UIButton*)sender;
-(void)moveCursorRightAction:(UIButton*)sender;
-(void)moveCursorUpAction:(UIButton*)sender;
-(void)moveCursorDownAction:(UIButton*)sender;
-(void)defineAction:(UIButton*)sender;
-(void)runCommandAction:(UIButton*)sender;

-(void)selectLineAction:(UIButton*)sender;
-(void)selectParagraphAction:(UIButton*)sender;
-(void)selectSentenceAction:(UIButton*)sender;
-(void)moveCursorPreviousWordAction:(UIButton*)sender;
-(void)moveCursorNextWordAction:(UIButton*)sender;
-(void)moveCursorStartOfLineAction:(UIButton*)sender;
-(void)moveCursorEndOfLineAction:(UIButton*)sender;
-(void)moveCursorStartOfParagraphAction:(UIButton*)sender;
-(void)moveCursorEndOfParagraphAction:(UIButton*)sender;
-(void)moveCursorStartOfSentenceAction:(UIButton*)sender;
-(void)moveCursorEndOfSentenceAction:(UIButton*)sender;
-(void)deleteForwardAction:(UIButton*)sender;

-(UIWindow*)keyWindow;

-(void)moveCursorContinuoslyWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate offset:(int)offset;
-(void)triggerImpactAndAnimationWithButton:(UIButton *)sender;
-(NSArray *)synthesizeIndexingForIndexOrOffset:(BOOL)offset descendingOffset:(BOOL)reverse numberOfItems:(int)itemsCount;
- (NSInteger)currentCursorPosition:(id <UITextInput, UITextInputTokenizer>)delegate;
-(void)moveCursorWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate offset:(int)offset;
-(void)moveCursorVerticalWithDelegate:(id<UITextInput>)delegate direction:(UITextLayoutDirection)direction;
-(BOOL)isRTLForDelegate:(id <UITextInput, UITextInputTokenizer>)delegate;
-(UITextRange *)selectedWordTextRangeWithDelegate:(id<UITextInput>)delegate;
-(UITextRange *)selectedWordTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextStorageDirection)direction;
-(UITextRange *)autoDirectionWordSelectedTextRangeWithDelegate:(id<UITextInput> )delegate;

-(UITextRange *)singleWordTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextStorageDirection)direction;
-(UITextRange *)lineExtremityTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextLayoutDirection)direction;
-(void)moveCursorSingleWordWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate direction:(UITextStorageDirection)direction;
-(void)moveCursorToLineExtremityWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate direction:(UITextLayoutDirection)direction;

-(NSDictionary *)getItemWithID:(NSString *)snippetID forKey:(NSString *)keyName identifierKey:(NSString *)identifier;
-(void)runCommand:(NSString *)cmd;
-(BOOL)isValidURL:(NSString *)urlString;

@end
