#import "DXDarwinOpenChannel.h"

FOUNDATION_EXPORT BOOL DXIsSensitiveOpenScheme(NSString *scheme);
FOUNDATION_EXPORT void DXOpenSystemApplication(NSString *bundleIdentifier, DXSystemOpenReply reply);
FOUNDATION_EXPORT void DXOpenSensitiveSystemURL(NSURL *url, DXSystemOpenReply reply);
FOUNDATION_EXPORT void DXOpenSystemShortcut(NSString *bundleIdentifier, NSString *shortcutType, DXSystemOpenReply reply);
FOUNDATION_EXPORT BOOL DXStartSystemOpenBroker(void);
