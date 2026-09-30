#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

static inline CGFloat DXPanelControlCircle(CGFloat width) { return MAX(0, MIN(58, width / 5 - 8)); }
static inline CGFloat DXPanelSystemControlsHeight(CGFloat width) { return DXPanelControlCircle(width) + 24 + 12 + 50 + 14; }
