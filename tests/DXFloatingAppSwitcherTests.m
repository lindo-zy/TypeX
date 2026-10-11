#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>
static id sharedSwitcher;
static BOOL noItem;
static NSUInteger additions;
static NSString *registeredBundle, *registeredScene;
static id registeredWindow;
static BOOL DXIsValidBundleIdentifier(NSString *s) { return [s hasPrefix:@"com.example."]; }
@interface SBDisplayItem : NSObject
+ (id)applicationDisplayItemWithBundleIdentifier:(id)bundle sceneIdentifier:(id)scene;
@end
@implementation SBDisplayItem
+ (id)applicationDisplayItemWithBundleIdentifier:(id)bundle sceneIdentifier:(id)scene {
    if (noItem) return nil;
    return @{ @"bundle": bundle, @"scene": scene };
}
@end
@interface SBMainSwitcherControllerCoordinator : NSObject
+ (id)sharedInstance;
@end
@implementation SBMainSwitcherControllerCoordinator
+ (id)sharedInstance { return sharedSwitcher; }
@end
@interface SwitcherFixture : NSObject
@property(nonatomic) BOOL existing;
@property(nonatomic) BOOL throws;
- (id)_appLayoutContainingDisplayItem:(id)item;
- (void)addAppLayoutForDisplayItem:(id)item windowScene:(id)window completion:(void (^)(void))completion;
@end
@implementation SwitcherFixture
- (id)_appLayoutContainingDisplayItem:(__unused id)item { return self.existing ? @"layout" : nil; }
- (void)addAppLayoutForDisplayItem:(id)item windowScene:(id)window completion:(void (^)(void))completion {
    if (self.throws) @throw [NSException exceptionWithName:@"Unavailable" reason:nil userInfo:nil];
    additions++; registeredBundle = item[@"bundle"]; registeredScene = item[@"scene"]; registeredWindow = window;
    if (completion) completion();
}
@end
@interface BadSwitcherFixture : NSObject
- (BOOL)addAppLayoutForDisplayItem:(id)item windowScene:(id)window completion:(void (^)(void))completion;
@end
@implementation BadSwitcherFixture
- (BOOL)addAppLayoutForDisplayItem:(__unused id)item windowScene:(__unused id)window completion:(__unused void (^)(void))completion {
    additions++; return YES;
}
@end
@interface FallbackSwitcherFixture : NSObject
- (void)addCenterRoleAppLayoutForDisplayItem:(id)item windowScene:(id)window completion:(void (^)(void))completion;
@end
@implementation FallbackSwitcherFixture
- (void)addCenterRoleAppLayoutForDisplayItem:(__unused id)item windowScene:(__unused id)window completion:(void (^)(void))completion {
    additions++; if (completion) completion();
}
@end
@interface SceneFixture : NSObject
@property(nonatomic, copy) NSString *identifier;
@end
@implementation SceneFixture
@end
#include "FloatingObjectHelpers.inc"
#include "FloatingSceneMatch.inc"
#include "FloatingSwitcher.inc"
#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        SceneFixture *scene = [SceneFixture new]; scene.identifier = @"sceneID:com.example.app-default";
        id window = [NSObject new];
        SwitcherFixture *fixture = [SwitcherFixture new]; sharedSwitcher = fixture;
        REQUIRE(DXFloatRegisterSwitcherCard(@"com.example.app", scene, window));
        REQUIRE(additions == 1 && [registeredBundle isEqual:@"com.example.app"] &&
                [registeredScene isEqual:scene.identifier] && registeredWindow == window);
        fixture.existing = YES;
        REQUIRE(DXFloatRegisterSwitcherCard(@"com.example.app", scene, window) && additions == 1);
        fixture.existing = NO; fixture.throws = YES;
        REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", scene, window) && additions == 1);
        REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.other", scene, window));
        REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", nil, window));
        REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", scene, nil));
        noItem = YES; REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", scene, window)); noItem = NO;
        sharedSwitcher = [NSObject new]; REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", scene, window));
        sharedSwitcher = [BadSwitcherFixture new]; REQUIRE(!DXFloatRegisterSwitcherCard(@"com.example.app", scene, window) && additions == 1);
        sharedSwitcher = [FallbackSwitcherFixture new]; REQUIRE(DXFloatRegisterSwitcherCard(@"com.example.app", scene, window) && additions == 2);
        printf("PASS: %lu production switcher assertions (scene identity, add/dedup, fallback, missing/ABI/exception guards)\n", (unsigned long)checks);
    }
    return 0;
}
