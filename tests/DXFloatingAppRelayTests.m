#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../DXFloatingAppInput.h"
@interface CardFixture : NSObject
@property(nonatomic) double displayed, start;
@property(nonatomic) NSUInteger starts, completions;
- (void)applyPinchScale:(CGFloat)scale phase:(DXFloatPinchPhase)phase;
@end
@implementation CardFixture
- (void)applyPinchScale:(CGFloat)scale phase:(DXFloatPinchPhase)phase {
    if (phase == DXFloatPinchBegan) { self.start = self.displayed; self.starts++; }
    self.displayed = phase == DXFloatPinchCancelled ? self.start : self.start * scale;
    if (phase == DXFloatPinchEnded || phase == DXFloatPinchCancelled) self.completions++;
}
@end
@interface RelayFixture : NSObject
@property(nonatomic) uint32_t inputNonce;
@property(nonatomic) uint8_t inputGesture;
@property(nonatomic) BOOL inputGestureFinished;
@property(nonatomic, strong) CardFixture *controller;
- (void)receivePinchWord:(uint64_t)word nonce:(uint32_t)nonce;
@end
@implementation RelayFixture
#include "FloatingRelay.inc"
@end
#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        RelayFixture *host = [RelayFixture new]; host.inputNonce = 71; host.controller = [CardFixture new];
        host.controller.displayed = 1;
        uint64_t begin = DXFloatPinchWord(71, 1, DXFloatPinchBegan, 1.1);
        [host receivePinchWord:begin nonce:71]; [host receivePinchWord:begin nonce:71];
        REQUIRE(host.controller.starts == 1 && fabs(host.controller.displayed - 1.1) < .001);
        [host receivePinchWord:DXFloatPinchWord(71, 1, DXFloatPinchChanged, 1.5) nonce:71];
        REQUIRE(host.controller.starts == 1 && host.controller.displayed == 1.5);
        uint64_t end = DXFloatPinchWord(71, 1, DXFloatPinchEnded, 2);
        [host receivePinchWord:end nonce:71]; [host receivePinchWord:end nonce:71];
        REQUIRE(host.controller.completions == 1 && host.controller.displayed == 2);
        [host receivePinchWord:DXFloatPinchWord(71, 2, DXFloatPinchEnded, .75) nonce:71];
        REQUIRE(host.controller.starts == 2 && host.controller.completions == 2 && host.controller.displayed == 1.5);
        [host receivePinchWord:DXFloatPinchWord(71, 3, DXFloatPinchChanged, 2) nonce:71];
        REQUIRE(host.controller.starts == 3 && host.controller.displayed == 3);
        [host receivePinchWord:DXFloatPinchWord(71, 3, DXFloatPinchCancelled, 1) nonce:71];
        REQUIRE(host.controller.displayed == 1.5 && host.controller.completions == 3);
        host.inputNonce = 72;
        [host receivePinchWord:DXFloatPinchWord(71, 4, DXFloatPinchChanged, 4) nonce:71];
        REQUIRE(host.controller.starts == 3 && host.controller.displayed == 1.5);
        [host receivePinchWord:DXFloatPinchWord(71, 4, DXFloatPinchChanged, 4) nonce:72];
        REQUIRE(host.controller.starts == 3);
        printf("PASS: %lu production relay assertions (coalesced start/end, duplicate begin/end, cancel, stale session)\n", (unsigned long)checks);
    }
    return 0;
}
