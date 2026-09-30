#import <Foundation/Foundation.h>
#import "DXKeyboardPanelGeometry.h"

int main(void) {
    @autoreleasepool {
        CGRect screen = CGRectMake(0, 0, 390, 844);
        CGRect top = CGRectMake(0, 470, 390, 44);
        CGRect keyboard = CGRectMake(0, 514, 390, 330);
        CGRect bottom = CGRectMake(69, 778, 261, 44);
        CGRect expected = CGRectMake(0, 470, 390, 374);
        // The first open can miss the keyboard notification. The live input
        // surface must still cover keys, candidate row and the bottom dock.
        CGRect measured = DXKeyboardPanelUnionCoverage(CGRectNull, top, screen, NO);
        measured = DXKeyboardPanelUnionCoverage(measured, keyboard, screen, YES);
        measured = DXKeyboardPanelUnionCoverage(measured, bottom, screen, NO);
        if (!CGRectEqualToRect(DXKeyboardPanelFullWidthCoverage(measured, screen), expected)) return 1;

        // Bottom entrance with no top toolbar still covers the whole keyboard.
        measured = DXKeyboardPanelUnionCoverage(CGRectNull, bottom, screen, NO);
        measured = DXKeyboardPanelUnionCoverage(measured, keyboard, screen, YES);
        if (!CGRectEqualToRect(DXKeyboardPanelFullWidthCoverage(measured, screen), keyboard)) return 2;

        // Keyboard notification + top entrance with the bottom toolbar disabled.
        measured = DXKeyboardPanelUnionCoverage(CGRectNull, keyboard, screen, YES);
        measured = DXKeyboardPanelUnionCoverage(measured, top, screen, NO);
        if (!CGRectEqualToRect(DXKeyboardPanelFullWidthCoverage(measured, screen), expected)) return 3;

        // A root container cannot expand coverage into the host app's content.
        if (!CGRectIsNull(DXKeyboardPanelUnionCoverage(CGRectNull, screen, screen, YES))) return 4;
        CGRect narrow = CGRectMake(50, 514, 150, 330);
        if (!CGRectIsNull(DXKeyboardPanelUnionCoverage(CGRectNull, narrow, screen, YES))) return 5;
        if (!CGRectIsNull(DXKeyboardPanelFullWidthCoverage(top, screen))) return 6;

        // Stale/offscreen and nonfinite frames must not corrupt good coverage.
        CGRect offscreen = CGRectMake(0, 900, 390, 330);
        if (!CGRectEqualToRect(DXKeyboardPanelUnionCoverage(expected, offscreen, screen, YES), expected)) return 7;
        CGRect invalid = CGRectMake(0, NAN, 390, 330);
        if (!CGRectEqualToRect(DXKeyboardPanelUnionCoverage(expected, invalid, screen, NO), expected)) return 8;
        if (!CGRectEqualToRect(DXKeyboardPanelUnionCoverage(expected, CGRectNull, screen, NO), expected)) return 9;
        if (!CGRectEqualToRect(DXKeyboardPanelUnionCoverage(expected, CGRectZero, screen, NO), expected)) return 10;

        // Keyboard transitions can temporarily extend below the screen.
        CGRect oversized = CGRectMake(0, 514, 390, 500);
        measured = DXKeyboardPanelUnionCoverage(CGRectNull, oversized, screen, YES);
        if (!CGRectEqualToRect(DXKeyboardPanelFullWidthCoverage(measured, screen), keyboard)) return 11;
        CGRect landscape = CGRectMake(0, 0, 844, 390);
        CGRect landscapeKeyboard = CGRectMake(0, 220, 844, 170);
        measured = DXKeyboardPanelUnionCoverage(CGRectNull, landscapeKeyboard, landscape, YES);
        if (!CGRectEqualToRect(DXKeyboardPanelFullWidthCoverage(measured, landscape), landscapeKeyboard)) return 12;
        NSLog(@"PASS 12 keyboard coverage checks (production geometry helpers)");
    }
    return 0;
}
