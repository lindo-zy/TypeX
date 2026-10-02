#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline CGRect DXGlobalPanelFrame(CGRect bounds, CGFloat safeTop, CGFloat safeBottom) {
    if (CGRectIsNull(bounds) || CGRectIsInfinite(bounds) || CGRectIsEmpty(bounds) ||
        !isfinite(safeTop) || !isfinite(safeBottom) || safeTop < 0 || safeBottom < 0) return CGRectNull;
    CGFloat width = MIN(500, MAX(0, bounds.size.width - 20));
    CGFloat bottom = safeBottom + 10;
    CGFloat height = MIN(520, MAX(0, bounds.size.height - safeTop - bottom - 20));
    if (width < 100 || height < 100) return CGRectNull;
    return CGRectMake(bounds.origin.x + (bounds.size.width - width) / 2,
        CGRectGetMaxY(bounds) - bottom - height, width, height);
}
