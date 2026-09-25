# System open routing

## Routes

| Action | Execution |
| --- | --- |
| Ordinary scheme or external HTTP(S) URL | One `UIApplication openURL:options:completionHandler:` call in the original host. No timeout, fallback, handler lookup, or automatic retry. |
| `prefs:`, `app-prefs:` (case insensitive) | Send the full expanded URL to SpringBoard; call `SBSOpenSensitiveURLAndUnlock` once on a serial worker, then activate `com.apple.Preferences` on the main queue after successful delivery. |
| `itms-services:` (case insensitive) | Use the same worker for the sensitive URL RPC; do not assume a foreground application for the system installation flow. |
| Native Bundle ID action | Send the identifier to SpringBoard; call its `launchApplicationWithIdentifier:suspended:NO` once. Check selector availability and the actual BOOL return ABI. |
| App action with PullOver enabled | Preserve the existing fingerprint bridge and installed receiver API. |
| In-app web browser | Preserve the existing Safari presentation. |

The SpringBoard server lives in TypeX.dylib and starts in the existing SpringBoard
constructor branch. The ordinary URL path is independent of this server. No code
or protocol change is required in WeChat, PullOver-X, or the settings UI.

The previous all-URL file relay and its CFPreferences status channel are removed.
The new transport never uses `/Library/TypeX/openrequest.plist`, a host container,
or a cfprefsd domain. Application activation does not synthesize a URL or attach
an undocumented `__LaunchURL` launch option. The native activation selector has
local precedent in PullOver-X's `POExternalActivationCoordinator.m` and
`PullOverViewController.m`; its actual availability remains runtime checked.

## Request lifetime

1. Encode kind, payload, random 64-bit ID and creation time in a binary plist.
   Prepend SHA-256 to detect incomplete or corrupted state words. This checksum
   does not authenticate the sender.
2. Store 64-bit words under notification names unique to the ID. Keep every
   registration alive. Publish the bounded size header after all words, then
   put the ID in the common doorbell's state and post once.
3. The server reconstructs the packet, checks size, digest, ID, field types and
   age, and deduplicates the ID before queueing execution on the main thread.
   Check the eight-second lifetime again immediately before execution.
   Sensitive requests keep that same deadline on the worker and before any
   follow-up foreground activation. A newer valid system action cancels the
   earlier request's pending foreground step.
4. The executor accepts only the two action kinds and validated payloads. Its
   result goes into a per-ID notification state and notification. For Settings,
   successful URL delivery is followed by one native foreground activation;
   this step does not resend the URL. No URL retry is performed.
5. The sender completes once and cancels all registrations. At ten seconds it
   reads reply state again before reporting an unknown outcome: a suspended
   host or a delayed notification must not overwrite an existing success.
   There is no automatic resend.

There are at most four pending requests per publisher, an 8192-byte packet cap,
a 2048-character sensitive-URL cap and a 256-character Bundle ID cap. Request
slots cannot mix bytes between publishers. The common doorbell is newest-wins:
simultaneous requests can coalesce, and an unconsumed request times out. A stopped
or absent server never causes a later fallback in the host. Suspended publishers
clean their registrations on resumption; process exit also releases notifyd's
registrations. Late UI errors are guarded by the toolbar generation, its original
window, host activation and elapsed time.

## Settings foreground correction

The user confirmed that 3.6.0 opens schemes and applications from WeChat and other
hosts. They also reported that `prefs:root=...` stalls the screen and leaves the
destination visible only in the app switcher. The source called the synchronous
SBS client entry point directly on SpringBoard's main queue and treated its return
as the entire operation. That call can hold up UI/activation processing while
waiting for the system service; its success does not establish foreground state.
The exact internal wait was not traced on a device.

The executor now keeps the potentially blocking client RPC off the main thread.
UIKit/native activation still runs on the main thread, using the same native
Bundle ID activation route that the user confirmed working. Settings activation
occurs only after successful URL delivery, so the original deep link is preserved
and is not delivered twice. Failed delivery does not open a plain Settings page.
Cancelled/expired work is rejected before the RPC and again before activation.
An RPC already entered cannot be cancelled; a late result cannot trigger the
additional foreground step. Ordinary URLs and native app-only dispatch retain
their existing paths.

Apple documents the state and cancellation APIs in
[Darwin notify](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/notify_register_signal.3.html).
The project already uses the same get/set-state interface for the PullOver bridge.

## Reproducible checks

Run `python3 tests/run-darwin-open-channel.py` on macOS. It compiles the actual
Foundation transport and runs independent sender/server processes against
notifyd. Coverage includes a 2048-character payload containing Chinese and URL
query punctuation, successful replies, repeated doorbells, repeated executor
replies, missing/corrupted words, oversized metadata and payload, absent server,
expiry while the main queue is blocked, a reply with no delivered notification,
and cancellation of pending registrations.

Run `python3 tests/run-sensitive-url-executor.py` for the production sensitive
executor with controlled delivery/activation blocks. A blocking RPC stand-in
waits for the main queue, proving the main loop can run while delivery is pending.
Checks cover unchanged URL data, delivery-before-activation order, main-thread
activation/reply, failure and exception paths, cancellation before/during delivery,
expiry before/during delivery, and `itms-services:` without Settings activation.
These tests verify scheduling and lifecycle logic, not Apple's private API behavior.

Run `./build-roothide-ios.sh` for the project's two RootHide artifacts. Tests
under this directory are not included by the tweak's root-level source wildcard.

These checks establish source, transport and package behavior. They do not
exercise iOS private launch APIs or WeChat UI behavior. Device connection and
device analysis were explicitly excluded from this change by the user.
