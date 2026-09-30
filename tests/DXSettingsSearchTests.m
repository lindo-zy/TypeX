#import <Foundation/Foundation.h>
#import "../DXSettingsSearch.h"
#import "../DXKeyboardPanelLayout.h"

static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"check %lu failed", (unsigned long)checks + 1); checks++; }
int main(void) {
    @autoreleasepool {
        NSArray *rows = @[@{@"text": @"独立入口", @"group": @NO},
                         @{@"text": @"快捷方式", @"group": @YES},
                         @{@"text": @"顶部设置", @"group": @NO},
                         @{@"text": @"滑动面板 支持左右", @"group": @NO},
                         @{@"text": @"应用", @"group": @YES},
                         @{@"text": @"ＡＩ Café", @"group": @NO}];
        NSMutableIndexSet *expected = [NSMutableIndexSet indexSetWithIndex:1]; [expected addIndex:3];
        check([DXSettingsSearchIndices(rows, @" 面板 ") isEqualToIndexSet:expected]);
        check([DXSettingsSearchIndices(rows, @"左右") isEqualToIndexSet:expected]);
        check([DXSettingsSearchIndices(rows, @"快捷方式") isEqualToIndexSet:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)]]);
        check([DXSettingsSearchIndices(rows, @"ai cafe") isEqualToIndexSet:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(4, 2)]]);
        check([DXSettingsSearchIndices(rows, @"独立") isEqualToIndexSet:[NSIndexSet indexSetWithIndex:0]]);
        check(!DXSettingsSearchIndices(rows, @"未找到").count);
        check(DXSettingsSearchIndices(rows, @" \n").count == rows.count);
        check(!DXSettingsSearchIndices(@[], @"测试").count);
        for (NSNumber *width in @[@0, @280, @343, @398, @1024]) {
            for (NSInteger columns = 3; columns <= 5; columns++) {
                for (NSNumber *scale in @[@0.7, @1, @1.2]) {
                    CGFloat w = width.doubleValue, s = scale.doubleValue;
                    check(DXKeyboardPanelContentHeight(0, w, columns, s) == 0);
                    CGFloat contentHeight = DXKeyboardPanelContentHeight(50, w, columns, s);
                    CGRect previous = CGRectZero;
                    for (NSUInteger index = 0; index < 50; index++) {
                        CGRect frame = DXKeyboardPanelItemFrame(index, w, columns, s);
                        check(CGRectGetMinX(frame) >= 0 && CGRectGetMaxX(frame) <= w + 0.01 && CGRectGetMaxY(frame) <= contentHeight + 0.01);
                        if (index) check(index % columns ? CGRectGetMinX(frame) + 0.01 >= CGRectGetMaxX(previous) : CGRectGetMinY(frame) + 0.01 >= CGRectGetMaxY(previous));
                        previous = frame;
                    }
                }
            }
        }
        NSLog(@"PASS: %lu settings search/layout checks (Chinese search, sections, clearing, narrow/large preview grids)", (unsigned long)checks);
    }
    return 0;
}
