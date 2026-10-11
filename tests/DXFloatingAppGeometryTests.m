#import <Foundation/Foundation.h>
#import "../DXFloatingAppGeometry.h"

#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.0001; }
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        for (NSValue *value in @[[NSValue valueWithSize:NSMakeSize(390, 844)],
                                [NSValue valueWithSize:NSMakeSize(844, 390)]]) {
            CGSize screen = value.sizeValue;
            // Nonzero safe left/right represent a landscape notch as well.
            CGRect available = CGRectMake(20, 55, screen.width - 40, screen.height - 90);
            CGSize base = CGSizeMake(available.size.width * .72, available.size.height * .72);
            for (NSInteger alignment = 0; alignment <= 2; alignment++) {
                for (NSNumber *request in @[@0, @0.8, @1, @1.2, @100, @(NAN)]) {
                    CGFloat zoom = DXFloatingAppZoom(base, available, request.doubleValue);
                    CGRect f = DXFloatingAppFrame(base, available, zoom, CGPointMake(2000, -2000), alignment, NO);
                    REQUIRE(isfinite(zoom) && zoom > 0);
                    REQUIRE(near(f.size.width / f.size.height, base.width / base.height));
                    REQUIRE(CGRectGetMinX(f) >= CGRectGetMinX(available) - .0001);
                    REQUIRE(CGRectGetMaxX(f) <= CGRectGetMaxX(available) + .0001);
                    REQUIRE(CGRectGetMinY(f) >= CGRectGetMinY(available) - .0001);
                    REQUIRE(CGRectGetMaxY(f) <= CGRectGetMaxY(available) + .0001);
                    REQUIRE(alignment != 0 || near(CGRectGetMinX(f), CGRectGetMinX(available)));
                    REQUIRE(alignment != 1 || near(CGRectGetMidX(f), CGRectGetMidX(available)));
                    REQUIRE(alignment != 2 || near(CGRectGetMaxX(f), CGRectGetMaxX(available)));
                }
            }
            CGPoint moved = CGPointMake(CGRectGetMidX(available), CGRectGetMidY(available));
            CGRect f = DXFloatingAppFrame(base, available, 1, moved, 0, YES);
            REQUIRE(near(CGRectGetMidX(f), moved.x) && near(CGRectGetMidY(f), moved.y));
            CGFloat limit = DXFloatingAppZoom(base, available, 100);
            REQUIRE(DXFloatingAppZoom(base, available, limit * .9) < limit);
            REQUIRE(DXFloatingAppZoom(base, available, 1.2) > 1);
            REQUIRE(near(DXFloatingAppZoom(available.size, available, 1), 1));
            REQUIRE(DXFloatingAppZoom(available.size, available, .8) < 1);
        }
        printf("PASS: %lu floating geometry assertions (dock, drag, aspect, bounds, repeated zoom, portrait/landscape/fullscreen)\n", (unsigned long)checks);
    }
    return 0;
}
