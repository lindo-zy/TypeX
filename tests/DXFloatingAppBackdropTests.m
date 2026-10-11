#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <stdbool.h>
#include <string.h>
#include "FloatingBackdrop.inc"

@interface UnsupportedLayer : NSObject
@property(nonatomic) NSInteger allowsHitTesting;
@end
@implementation UnsupportedLayer
@end

@interface ThrowingLayer : NSObject
- (bool)allowsHitTesting;
- (void)setAllowsHitTesting:(bool)value;
@end
@implementation ThrowingLayer
- (bool)allowsHitTesting { return false; }
- (void)setAllowsHitTesting:(__unused bool)value { @throw [NSException exceptionWithName:@"Unavailable" reason:nil userInfo:nil]; }
@end

@interface IgnoringLayer : NSObject
- (bool)allowsHitTesting;
- (void)setAllowsHitTesting:(bool)value;
@end
@implementation IgnoringLayer
- (bool)allowsHitTesting { return false; }
- (void)setAllowsHitTesting:(__unused bool)value {}
@end

#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        REQUIRE(!DXFloatConfigureBackdropHitTesting(nil));
        REQUIRE(!DXFloatConfigureBackdropHitTesting([NSObject new]));
        UnsupportedLayer *wrongABI = [UnsupportedLayer new];
        REQUIRE(!DXFloatConfigureBackdropHitTesting(wrongABI));
        REQUIRE(wrongABI.allowsHitTesting == 0);
        REQUIRE(!DXFloatConfigureBackdropHitTesting([ThrowingLayer new]));
        REQUIRE(!DXFloatConfigureBackdropHitTesting([IgnoringLayer new]));

        // Exercise the real host QuartzCore properties, not simulated setter calls.
        // This confirms capability/configuration only, not iOS WindowServer routing.
        CALayer *backdrop = [CALayer layer];
        backdrop.bounds = CGRectMake(0, 0, 390, 844);
        CGColorRef clear = CGColorCreateGenericGray(0, 0);
        backdrop.backgroundColor = clear;
        REQUIRE(DXFloatConfigureBackdropHitTesting(backdrop));
        REQUIRE(((bool (*)(id, SEL))objc_msgSend)(backdrop, NSSelectorFromString(@"allowsHitTesting")));
        REQUIRE(((bool (*)(id, SEL))objc_msgSend)(backdrop, NSSelectorFromString(@"hitTestsAsOpaque")));
        REQUIRE(CGColorGetAlpha(backdrop.backgroundColor) == 0);
        REQUIRE(backdrop.opacity == 1 && !backdrop.hidden);
        REQUIRE(CGRectEqualToRect(backdrop.bounds, CGRectMake(0, 0, 390, 844)));
        REQUIRE(DXFloatConfigureBackdropHitTesting(backdrop));
        REQUIRE(CGColorGetAlpha(backdrop.backgroundColor) == 0);
        CGColorRelease(clear);
        printf("PASS: %lu backdrop assertions (native QuartzCore, transparent bounds, repeated setup, missing/ABI/exception/readback guards)\n", (unsigned long)checks);
    }
    return 0;
}
