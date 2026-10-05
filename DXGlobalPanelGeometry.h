#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// contentHeight is the panel's natural content height (header + message +
// controls + action grid). The panel fits it, stretched to a 100pt floor and
// clamped to the on-screen space; overflow scrolls inside the panel.
// Status-bar presentations anchor to the top edge, everything else keeps the
// bottom-edge placement.
static inline CGRect DXGlobalPanelFrame(CGRect bounds, CGFloat safeTop, CGFloat safeBottom,
    CGFloat contentHeight, BOOL topAnchored) {
    if (CGRectIsNull(bounds) || CGRectIsInfinite(bounds) || CGRectIsEmpty(bounds) ||
        !isfinite(safeTop) || !isfinite(safeBottom) || !isfinite(contentHeight) ||
        safeTop < 0 || safeBottom < 0 || contentHeight < 0) return CGRectNull;
    CGFloat width = MIN(500, MAX(0, bounds.size.width - 20));
    CGFloat inset = 10;
    CGFloat available = MAX(0, bounds.size.height - safeTop - safeBottom - inset * 2);
    CGFloat height = MIN(MAX(contentHeight, 100), available);
    if (width < 100 || height < 100) return CGRectNull;
    CGFloat y = topAnchored ? bounds.origin.y + safeTop + inset
        : CGRectGetMaxY(bounds) - safeBottom - inset - height;
    return CGRectMake(bounds.origin.x + (bounds.size.width - width) / 2, y, width, height);
}
