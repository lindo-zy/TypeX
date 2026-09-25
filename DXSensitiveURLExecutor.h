#import "DXDarwinOpenChannel.h"

typedef BOOL (^DXSensitiveURLDelivery)(NSURL *url);
typedef DXSystemOpenResult (^DXSensitiveURLActivation)(NSString *bundleIdentifier);

// The delivery block is a potentially blocking SBS client RPC, never UIKit.
// Activation and reply run on the main queue. No retry or main-thread wait.
FOUNDATION_EXPORT void DXExecuteSensitiveURL(NSURL *url, NSDate *deadline,
    NSProgress *request, DXSensitiveURLDelivery deliver,
    DXSensitiveURLActivation activate, DXSystemOpenReply reply);
