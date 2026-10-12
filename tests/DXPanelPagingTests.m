#import <Foundation/Foundation.h>
#import "../DXKeyboardPanelLayout.h"

static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"paging check %lu failed", (unsigned long)checks + 1); checks++; }
int main(void) {
    @autoreleasepool {
        for (NSInteger columns = 3; columns <= 5; columns++) {
            NSUInteger capacity = (NSUInteger)columns * 3;
            check(DXPanelPageCapacity(columns) == capacity);
            for (NSNumber *number in @[@0, @1, @(capacity - 1), @(capacity), @(capacity + 1), @(capacity * 2), @(capacity * 3 + 2)]) {
                NSUInteger count = number.unsignedIntegerValue;
                NSUInteger expectedPages = (count + capacity - 1) / capacity;
                check(DXPanelPageCount(count, columns) == expectedPages);
                for (NSNumber *width in @[@0, @280, @398, @500]) {
                    CGFloat w = width.doubleValue;
                    for (NSNumber *scale in @[@0.7, @1, @1.2]) {
                        CGFloat s = scale.doubleValue;
                        CGFloat height = DXPanelPageHeight(count, w, columns, s);
                        check(height <= 3 * DXKeyboardPanelRowHeight(w, columns, s));
                        check((count == 0) == (height == 0));
                        check(CGRectEqualToRect(DXPanelPagedItemFrame(count, count, w, columns, s), CGRectZero));
                        for (NSUInteger index = 0; index < count; index++) {
                            CGRect frame = DXPanelPagedItemFrame(index, count, w, columns, s);
                            if (!w) { check(CGRectEqualToRect(frame, CGRectZero)); continue; }
                            NSUInteger page = index / capacity;
                            CGFloat offset = DXPanelPageOffset(page, expectedPages, w);
                            check(DXPanelPageAtOffset(offset, expectedPages, w) == page);
                            check(CGRectGetMinX(frame) >= offset && CGRectGetMaxX(frame) <= offset + w + 0.01);
                            check(CGRectGetMinY(frame) >= 0 && CGRectGetMaxY(frame) <= height + 0.01);
                            check(fabs(CGRectGetMinY(frame) - ((index % capacity) / columns) * DXKeyboardPanelRowHeight(w, columns, s)) < 0.01);
                            if (index % capacity) {
                                CGRect previous = DXPanelPagedItemFrame(index - 1, count, w, columns, s);
                                check(index % columns ? CGRectGetMinX(frame) + 0.01 >= CGRectGetMaxX(previous)
                                    : CGRectGetMinY(frame) + 0.01 >= CGRectGetMaxY(previous));
                            }
                            if (page + 1 < expectedPages) check(DXPanelPageOffset(page + 1, expectedPages, w) < offset);
                        }
                    }
                }
            }
        }
        check(DXPanelPageAtOffset(-100, 3, 300) == 2);
        check(DXPanelPageAtOffset(9999, 3, 300) == 0);
        check(DXPanelPageAtOffset(NAN, 3, 300) == 0);
        check(DXPanelPageAtOffset(300, 3, 0) == 0);
        check(DXPanelPageOffset(99, 3, 300) == 0);
        check(DXPanelPageOffset(0, 0, 300) == 0);
        NSLog(@"PASS: %lu paging geometry checks (3-row limits, boundaries, order, rightward next page, final partial page)", (unsigned long)checks);
    }
    return 0;
}
