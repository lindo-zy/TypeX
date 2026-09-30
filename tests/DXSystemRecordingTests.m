#import "../DXSystemRecordingSession.h"

@interface DXRecorderSpy : NSObject
@property(nonatomic) BOOL recording;
@property(nonatomic) BOOL systemRecording;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL microphone;
@property(nonatomic) BOOL throws;
@property(nonatomic) NSUInteger starts;
@property(nonatomic) NSUInteger stops;
@property(nonatomic, copy) void (^completion)(NSError *);
- (BOOL)isRecording;
- (BOOL)isAvailable;
- (void)startSystemRecordingWithMicrophoneEnabled:(BOOL)enabled handler:(void (^)(NSError *))handler;
- (void)stopSystemRecording:(void (^)(NSError *))handler;
@end
@implementation DXRecorderSpy
- (BOOL)isRecording { return self.recording; }
- (BOOL)isAvailable { return self.available; }
- (void)startSystemRecordingWithMicrophoneEnabled:(BOOL)enabled handler:(void (^)(NSError *))handler {
    self.starts++; self.microphone = enabled;
    if (self.throws) [NSException raise:@"NativeRecordingException" format:@"test"];
    self.completion = handler;
}
- (void)stopSystemRecording:(void (^)(NSError *))handler { self.stops++; self.completion = handler; }
@end

// Same selectors, incompatible ABI: production must refuse before invocation.
@interface DXWrongRecorderSpy : NSObject
@property(nonatomic) NSUInteger calls;
- (BOOL)isRecording;
- (BOOL)systemRecording;
- (BOOL)isAvailable;
- (void)startSystemRecordingWithMicrophoneEnabled:(id)enabled handler:(id)handler;
@end
@implementation DXWrongRecorderSpy
- (BOOL)isRecording { return NO; }
- (BOOL)systemRecording { return NO; }
- (BOOL)isAvailable { return YES; }
- (void)startSystemRecordingWithMicrophoneEnabled:(id)enabled handler:(id)handler { self.calls++; }
@end

static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"check %lu failed", (unsigned long)checks + 1); checks++; }
static void drain(double seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static DXRecorderSpy *recorder(void) { DXRecorderSpy *spy = [DXRecorderSpy new]; spy.available = YES; return spy; }

int main(void) {
    @autoreleasepool {
        DXSystemRecordingSession *session = [DXSystemRecordingSession new];
        DXRecorderSpy *spy = recorder();
        __block NSUInteger replies = 0;
        __block DXSystemOpenResult result = 0;
        DXSystemOpenReply reply = ^(DXSystemOpenResult value) { check(NSThread.isMainThread); replies++; result = value; };
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(spy.starts == 1 && !spy.microphone && !replies);
        [session toggleRecorder:spy microphoneEnabled:YES reply:reply];
        check(result == DXSystemOpenBusy && replies == 1 && spy.starts == 1);
        void (^oldCompletion)(NSError *) = spy.completion;
        spy.recording = YES; spy.systemRecording = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ oldCompletion(nil); oldCompletion(nil); });
        drain(0.1);
        check(result == DXSystemOpenSucceeded && replies == 2);
        [session toggleRecorder:spy microphoneEnabled:YES reply:reply];
        check(spy.stops == 1 && spy.starts == 1 && replies == 2);
        oldCompletion(nil); drain(0.01);
        check(replies == 2); // Late start cannot complete this stop.
        spy.recording = NO; spy.systemRecording = NO; spy.completion(nil); drain(0.01);
        check(result == DXSystemOpenSucceeded && replies == 3);
        [session toggleRecorder:spy microphoneEnabled:YES reply:reply];
        check(spy.starts == 2 && spy.microphone);
        spy.completion([NSError errorWithDomain:@"ReplayKitDenied" code:17 userInfo:nil]); drain(0.01);
        check(result == DXSystemOpenFailed && replies == 4);

        spy.recording = YES; spy.systemRecording = NO;
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenBusy && spy.stops == 1 && spy.starts == 2);
        spy.recording = NO; spy.systemRecording = YES;
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenBusy && spy.starts == 2);
        spy.systemRecording = NO; spy.available = NO;
        [session toggleRecorder:spy microphoneEnabled:YES reply:reply];
        check(result == DXSystemOpenUnavailable && spy.starts == 2);
        [session toggleRecorder:nil microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenUnavailable);
        DXWrongRecorderSpy *wrong = [DXWrongRecorderSpy new];
        [session toggleRecorder:wrong microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenUnavailable && wrong.calls == 0);
        // Stopping remains available even if a new start is forbidden.
        spy.systemRecording = YES; spy.recording = YES;
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(spy.stops == 2);
        spy.completion(nil); drain(0.01);
        check(result == DXSystemOpenSucceeded);
        spy.recording = NO; spy.systemRecording = NO; spy.available = YES; spy.throws = YES;
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenUnavailable && spy.starts == 3);
        spy.throws = NO;

        // Two pending native calls time out concurrently. Neither is retried;
        // only a native reply or a verified terminal state releases its guard.
        DXSystemRecordingSession *lateSession = [DXSystemRecordingSession new];
        DXRecorderSpy *late = recorder();
        __block NSUInteger lateReplies = 0;
        __block DXSystemOpenResult lateResult = 0;
        [lateSession toggleRecorder:late microphoneEnabled:NO reply:^(DXSystemOpenResult value) { lateReplies++; lateResult = value; }];
        [session toggleRecorder:spy microphoneEnabled:YES reply:reply];
        NSUInteger before = replies;
        void (^timedOutCompletion)(NSError *) = spy.completion;
        drain(7.65);
        check(result == DXSystemOpenTimedOut && replies == before + 1 && spy.starts == 4 && spy.stops == 2);
        check(lateResult == DXSystemOpenTimedOut && lateReplies == 1 && late.starts == 1);
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(result == DXSystemOpenBusy && spy.starts == 4);
        spy.recording = YES; spy.systemRecording = YES;
        [session toggleRecorder:spy microphoneEnabled:NO reply:reply];
        check(spy.stops == 3 && spy.starts == 4);
        before = replies; timedOutCompletion(nil); drain(0.01);
        check(replies == before); // Timed-out start cannot acknowledge the new stop.
        spy.completion(nil); drain(0.01);
        check(replies == before + 1 && result == DXSystemOpenSucceeded);
        late.completion(nil); late.completion(nil); drain(0.01);
        check(lateReplies == 1); // No second transport reply after timeout.
        [lateSession toggleRecorder:late microphoneEnabled:YES reply:^(DXSystemOpenResult value) { lateReplies++; lateResult = value; }];
        check(late.starts == 2 && late.microphone);
        late.completion(nil); drain(0.01);
        check(lateResult == DXSystemOpenSucceeded && lateReplies == 2);
        NSLog(@"PASS: %lu recording checks (native async replies, mic flag, stop, ABI rejection, busy guard, duplicate/late replies, timeout without retry)", (unsigned long)checks);
    }
    return 0;
}
