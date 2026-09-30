#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Shared by the keyboard surface and the Settings preview. Units are points;
// content scale affects the circles and labels, never the number of columns.
static inline CGFloat DXKeyboardPanelCircle(CGFloat width, NSInteger columns, CGFloat scale) {
    return MAX(0, MIN(54 * scale, width / MAX(1, columns) - 16));
}
static inline CGFloat DXKeyboardPanelRowHeight(CGFloat width, NSInteger columns, CGFloat scale) {
    return DXKeyboardPanelCircle(width, columns, scale) + 42 * scale;
}
static inline CGRect DXKeyboardPanelItemFrame(NSUInteger index, CGFloat width, NSInteger columns, CGFloat scale) {
    columns = MAX(1, columns);
    CGFloat itemWidth = width / columns;
    CGFloat height = DXKeyboardPanelRowHeight(width, columns, scale);
    return CGRectMake((index % columns) * itemWidth, (index / columns) * height, itemWidth, height);
}
static inline CGFloat DXKeyboardPanelContentHeight(NSUInteger count, CGFloat width, NSInteger columns, CGFloat scale) {
    return ceil((double)count / MAX(1, columns)) * DXKeyboardPanelRowHeight(width, columns, scale);
}
