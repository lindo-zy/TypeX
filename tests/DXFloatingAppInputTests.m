#import <UIKit/UIKit.h>
#import "../DXFloatingAppInput.m"

@implementation UIGestureRecognizer
- (instancetype)initWithTarget:(__unused id)target action:(__unused SEL)action { return [super init]; }
@end
@implementation UIPinchGestureRecognizer
@end
@implementation UIWindow
- (instancetype)init { if ((self = [super init])) _recognizers = [NSMutableArray array]; return self; }
- (void)addGestureRecognizer:(UIGestureRecognizer *)gesture { [self.recognizers addObject:gesture]; }
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gesture { [self.recognizers removeObject:gesture]; }
@end
@implementation UITouch
@end
@implementation UISceneSession
@end
@implementation UIScene
@end
@implementation UIWindowScene
- (NSString *)_sceneIdentifier { return self.testIdentifier; }
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
@end
#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        uint32_t nonce = 9876;
        uint8_t serial; DXFloatPinchPhase phase; double scale;
        for (NSUInteger p = 0; p <= 3; p++) {
            for (double value = .1; value < 3; value += .1) {
                uint64_t word = DXFloatPinchWord(nonce, 255, (DXFloatPinchPhase)p, value);
                REQUIRE(DXFloatDecodePinch(word, nonce, &serial, &phase, &scale));
                REQUIRE(serial == 255 && phase == p && fabs(scale - value) < .001);
                REQUIRE(!DXFloatDecodePinch(word, nonce + 1, &serial, &phase, &scale));
            }
        }
        REQUIRE(DXFloatPinchWord(nonce, 1, DXFloatPinchChanged, NAN) == 0);
        REQUIRE(DXFloatPinchWord(nonce, 1, DXFloatPinchChanged, -1) == 0);
        REQUIRE(!DXFloatDecodePinch(DXFloatPinchWord(nonce, 1, DXFloatPinchChanged, 1) | 0x80000000,
                                  nonce, &serial, &phase, &scale));
        int sessionToken, sceneToken, eventToken;
        REQUIRE(notify_register_check(DXFloatInputSessionName.UTF8String, &sessionToken) == NOTIFY_STATUS_OK);
        REQUIRE(notify_register_check(DXFloatInputSceneName(getpid()).UTF8String, &sceneToken) == NOTIFY_STATUS_OK);
        REQUIRE(notify_register_check(DXFloatInputName(getpid()).UTF8String, &eventToken) == NOTIFY_STATUS_OK);
        UIWindowScene *hosted = [UIWindowScene new], *normal = [UIWindowScene new];
        hosted.testIdentifier = @"sceneID:com.example.target-default";
        normal.testIdentifier = @"sceneID:com.example.target-other";
        hosted.session = normal.session = [UISceneSession new]; hosted.session.role = UIWindowSceneSessionRoleApplication;
        UIWindow *a = [UIWindow new], *b = [UIWindow new];
        a.windowScene = hosted; b.windowScene = normal; hosted.windows = @[a]; normal.windows = @[b];
        UIApplication.sharedApplication.connectedScenes = [NSSet setWithObjects:hosted, normal, nil];
        notify_set_state(sceneToken, DXFloatInputSceneHash(hosted.testIdentifier));
        notify_set_state(sessionToken, DXFloatInputSessionWord(getpid(), nonce));
        DXFloatingAppInputClient *client = [DXFloatingAppInputClient new];
        int clientToken; notify_register_check(DXFloatInputSessionName.UTF8String, &clientToken); client.sessionToken = clientToken;
        [client refresh];
        REQUIRE(a.recognizers.count == 1 && b.recognizers.count == 0);
        [client refresh]; REQUIRE(a.recognizers.count == 1);
        UIPinchGestureRecognizer *pinch = a.recognizers.firstObject;
        UITouch *touch = [UITouch new]; touch.window = a;
        REQUIRE([client gestureRecognizer:pinch shouldReceiveTouch:touch]);
        touch.window = b; REQUIRE(![client gestureRecognizer:pinch shouldReceiveTouch:touch]);
        REQUIRE([client gestureRecognizer:pinch shouldRecognizeSimultaneouslyWithGestureRecognizer:[UIGestureRecognizer new]]);
        REQUIRE(![client gestureRecognizer:pinch shouldRecognizeSimultaneouslyWithGestureRecognizer:[UIPinchGestureRecognizer new]]);
        REQUIRE([client gestureRecognizer:pinch shouldBeRequiredToFailByGestureRecognizer:[UIPinchGestureRecognizer new]]);
        pinch.state = UIGestureRecognizerStateBegan; pinch.scale = 1; [client pinch:pinch];
        pinch.state = UIGestureRecognizerStateChanged; pinch.scale = 1.5; [client pinch:pinch];
        uint64_t word = 0; notify_get_state(eventToken, &word);
        REQUIRE(DXFloatDecodePinch(word, nonce, &serial, &phase, &scale) && serial == 1 && phase == DXFloatPinchChanged && scale == 1.5);
        notify_set_state(sessionToken, DXFloatInputSessionWord(getpid(), nonce + 1));
        [client refresh];
        REQUIRE(a.recognizers.count == 1 && a.recognizers.firstObject != pinch);
        pinch.scale = 3; [client pinch:pinch];
        uint64_t unchanged = 0; notify_get_state(eventToken, &unchanged); REQUIRE(unchanged == word);
        notify_set_state(sessionToken, 0); [client refresh];
        REQUIRE(a.recognizers.count == 0 && b.recognizers.count == 0 && ![client isCurrent]);
        notify_cancel(eventToken); notify_cancel(sceneToken); notify_cancel(sessionToken);
        printf("PASS: %lu production input assertions (wire, nonce, Scene filtering, recognizer priority, scale relay, replacement/revocation)\n", (unsigned long)checks);
    }
    return 0;
}
