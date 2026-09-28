#!/usr/bin/env python3
"""Run the production text dispatch method with Foundation spies, without UIKit."""
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
source = (ROOT / "DXCollectionView.m").read_text()
method = source[source.index("-(void)performTextCustomAction:"):
                source.index("// In-app open for the url type.")]
key = re.search(r'^#define kCustomActionTextRecordsKey .+$',
                (ROOT / "common.h").read_text(), re.M).group()
harness = r'''
#import <Foundation/Foundation.h>
#define LOCALIZED(key) key
@class UIButton;
@interface TextActionSpy : NSObject
@property (nonatomic, copy) NSString *inserted;
@property (nonatomic, copy) NSArray *choices;
@property (nonatomic, copy) NSString *message;
@property (nonatomic) NSUInteger dismissals;
- (void)performTextCustomAction:(NSDictionary *)entry sender:(UIButton *)sender;
- (void)dismissSubActionPanelAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)showCustomActionMessage:(NSString *)message;
- (void)insertTextIntoInputField:(NSString *)text;
- (void)presentActionChooserForButton:(UIButton *)button selectors:(NSArray *)selectors textRecords:(NSArray *)records;
@end
static TextActionSpy *DXActiveSubActionPanelOwner;
@implementation TextActionSpy
- (void)dismissSubActionPanelAnimated:(BOOL)animated completion:(void (^)(void))completion { self.dismissals++; }
- (void)showCustomActionMessage:(NSString *)message { self.message = message; }
- (void)insertTextIntoInputField:(NSString *)text { self.inserted = text; }
- (void)presentActionChooserForButton:(UIButton *)button selectors:(NSArray *)selectors textRecords:(NSArray *)records { self.choices = records; }
PRODUCTION_METHOD
@end
static NSUInteger checks;
static void check(NSDictionary *entry, NSString *inserted, NSArray *choices, BOOL error) {
    TextActionSpy *view = [TextActionSpy new];
    DXActiveSubActionPanelOwner = [TextActionSpy new];
    [view performTextCustomAction:entry sender:nil];
    NSCAssert((view.inserted == inserted || [view.inserted isEqual:inserted]) &&
              (view.choices == choices || [view.choices isEqual:choices]) &&
              (view.message != nil) == error && DXActiveSubActionPanelOwner.dismissals == 1,
              @"Text dispatch mismatch: %@", entry);
    checks++;
}
int main(void) {
    @autoreleasepool {
        // Literal content must survive byte-for-byte, including old markers.
        NSString *literal = @"  你好👋\n{{clipboard}} {{selection}} {{date1}} @@@\n ";
        check(@{@"textrecords": @[literal]}, literal, nil, NO);
        NSArray *multiple = @[literal, @"second\nline", @"second\nline"];
        check(@{@"textrecords": multiple}, nil, multiple, NO);
        check(@{@"textrecords": @[@" \n\t"]}, @" \n\t", nil, NO);
        check(@{@"link": @"old template"}, nil, nil, YES);
        check(@{@"textrecords": @[], @"link": @"old"}, nil, nil, YES);
        check(@{@"textrecords": @"wrong type"}, nil, nil, YES);
        check(@{@"textrecords": @[[NSNull null], @42, @{}, @""]}, nil, nil, YES);
        check(@{@"textrecords": @[@42, @"valid", @""]}, @"valid", nil, NO);
        check(@{}, nil, nil, YES);
        NSLog(@"PASS: %lu text dispatch checks (literal content, list order, malformed records, old-format rejection)", (unsigned long)checks);
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="typex-text-tests-") as tmp:
    tmp = pathlib.Path(tmp)
    unit = tmp / "TextActionTests.m"
    unit.write_text(key + "\n" + harness.replace("PRODUCTION_METHOD", method))
    binary = tmp / "text-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Werror",
                    "-framework", "Foundation", str(unit), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=15)
