#import "common.h"
#import "TypeX.h"

extern id delegate;
extern UIKeyboardImpl *kbImpl;
extern UIColor *currentTintColor;
extern UIColor *currentBackgroundTintColor;
extern BOOL isLandscape;
extern NSMutableDictionary *prefs;
extern BOOL isDictating;
extern BOOL toggledOn;
extern UIKeyboardDockView *dockView;
//extern BOOL isSandboxed;
extern CGPoint startPosition;
extern CGPoint endPosition;
extern NSDate *prevTime;
extern BOOL singleTapDictationEnabled;
extern BOOL singleTapGlobeEnabled;
extern BOOL isTrackPadMode;
extern BOOL isSpringBoard;
extern BOOL isApplication;
extern BOOL isSafari;
extern BOOL shouldPerformBatchUpdate;
//extern BOOL shouldSendScrollExecution;
extern NSString *key;
extern BOOL isDraggedGesture;
extern UIKeyboardDockView *dockV;
extern BOOL useShortenedLabel;
extern NSBundle *tweakBundle;
extern BOOL firstInit;
extern DXStudlyCapsType spongebobEntropy;

extern CGFloat heightOffset;

#ifdef __cplusplus
extern "C" {
#endif

BOOL preferencesBool(NSString* key, BOOL fallback);
float preferencesFloat(NSString* key, float fallback);
int preferencesInt(NSString* key, int fallback);
NSString *preferencesSelectorForIdentifier(NSString* identifier, int selectorNum, int gestureType, NSString *fallback);
NSString *preferencesSelectorForIdentifierScoped(NSString* identifier, int selectorNum, int gestureType, NSString *fallback, NSString *configuration);
NSArray<NSString *> *preferencesSubActionSelectorsForIdentifier(NSString* identifier, NSString *configuration);

#ifdef __cplusplus
}
#endif
