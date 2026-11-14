# Capture on macOS: what is documented, and what to measure

This note is for Cody Chen, building Context Assistant, Capture Lab, and Capture Diagnostics. It describes public APIs. It is not a procedure for reading a protected window, hiding a window from a proctor, or avoiding a Screen Recording prompt.

Context Assistant captures one window the user selects, with Screen Recording permission, through ScreenCaptureKit. If that capture is blank or fails, the assistant stops. Capture Lab changes `NSWindow` properties on its own windows only. Capture Diagnostics calls each public capture API once and writes JSON. It does not display the pixels and it does not treat one API's frame as a substitute for another.

## Windows `SetWindowDisplayAffinity` and `NSWindow.sharingType`

Windows lets a process mark its own window with `SetWindowDisplayAffinity`:

| Value | Meaning on Windows |
| --- | --- |
| `WDA_NONE` | Normal. The window may be captured by software that is allowed to capture. |
| `WDA_MONITOR` | Older DRM affinity. Content is intended for the physical monitor. |
| `WDA_EXCLUDEFROMCAPTURE` | The window asks to be left out of capture (Windows 10 version 2004 and later). |

The macOS property developers reach for, for their own window, is `NSWindow.sharingType` (`NSWindow.SharingType`):

| Case | AppKit value | Documented role |
| --- | --- | --- |
| `.readOnly` | `NSWindowSharingReadOnly` (1) | Default. Other processes may read the window's contents. |
| `.none` | `NSWindowSharingNone` (0) | The historical "do not share this window" value. |
| `.readWrite` | `NSWindowSharingReadWrite` (2) | Legacy. Do not use it for new code. |

Apple's AppKit reference describes `sharingType` as the level of access other processes have to the window's content. The older CoreGraphics window list header said that an on-screen window with sharing type `kCGWindowSharingNone` is not included in the image produced by `CGWindowListCreateImage`.

That is the documented analogy: both APIs are a request by the window's owner, about that window. They are not a capture API, and they are not a promise that every capture path on every OS version implements the request the same way. Context Assistant never sets `.none`. Its overlay sets `.readOnly` and the opacity slider cannot go below 55%.

ScreenCaptureKit's own sample excludes the capturing app from a display capture by leaving that app out of the `SCContentFilter`. That filter decides what the capturing app asks for. It does not hide the app from some other process's capture.

## ScreenCaptureKit

ScreenCaptureKit (macOS 12.3 and later) is the supported way to capture displays, apps, and windows.

The pieces this repo uses:

- `SCShareableContent` lists windows, apps, and displays the user is allowed to know about. Listing is already a privileged call. It requires Screen Recording permission and shows the system prompt if the app has not been decided.
- `SCContentSharingPicker` (macOS 14) is the system UI for choosing what to share. Context Assistant presents it in single-window mode and keeps the `SCContentFilter` the user confirms. Cancelling the picker captures nothing.
- `SCContentFilter(desktopIndependentWindow:)` limits a capture to one `SCWindow`.
- `SCScreenshotManager.captureImage` (macOS 14) takes one still frame. This is the only capture call in the assistant pipeline.
- `SCScreenshotManager.captureSampleBuffer` and `SCStream` are used by Capture Diagnostics as separate probes. The assistant does not call them.
- A capture that is running as an `SCStream` shows the system screen-recording indicator. There is no public switch to hide that indicator, and this repo does not try to add one.

`SCStream` can attach a frame status. `SCFrameStatus.blank` means the frame has no shareable content. Capture Diagnostics records that and ends that probe. It does not wait for a later frame in the hope that protected content appears.

## `CGWindowListCreateImage`

`CGWindowListCreateImage` is the legacy CoreGraphics call. Apple deprecated it in macOS 14 with the replacement "use ScreenCaptureKit". macOS 15 release notes say apps that keep using deprecated capture APIs such as `CGWindowListCreateImage` and `CGDisplayStream` can trigger a system alert, and that developers should move to ScreenCaptureKit and `SCContentSharingPicker`.

Historical limits, from the header and from how the API behaved before ScreenCaptureKit:

- It only returns windows the window server considers shareable. `kCGWindowSharingNone` was defined as excluded.
- It requires a Quartz GUI session. A missing Screen Recording grant often yields `NULL` rather than a useful error.
- It does not understand ScreenCaptureKit filters, and it is not a second chance after ScreenCaptureKit returns a blank frame.

Whether the symbol still exists, returns `NULL`, or returns pixels depends on the SDK and the OS version. Capture Diagnostics resolves `CGWindowListCreateImage` with `dlsym` so a newer SDK that no longer declares it can still compile. It calls that function once, with `kCGWindowListOptionIncludingWindow`, `kCGWindowImageBoundsIgnoreFraming`, and `kCGWindowImageBestResolution`. If the symbol is missing, the JSON says so. The assistant binary does not contain this probe.

## Screen Recording permission and TCC

Screen Recording is a Transparency, Consent, and Control (TCC) privacy grant. It is keyed to the app's bundle identity and code signature. The usage string is `NSScreenCaptureUsageDescription` in Info.plist. The system shows that string in the prompt.

Useful public checks:

- `CGPreflightScreenCaptureAccess()` reports the current grant and does not prompt.
- `CGRequestScreenCaptureAccess()` prompts. A process the user has already denied is not prompted again until the grant is reset.
- ScreenCaptureKit's user-declined error is `SCStreamErrorUserDeclined` (`-3801` in `SCStreamErrorDomain`).

Reset the grant for one bundle id with:

```bash
tccutil reset ScreenCapture dev.codychen.ContextAssistant
```

Quit the app first. After a grant, some macOS versions only notice it the next time the process starts. If "Check again" stays off, quit and reopen.

macOS 15 (Sequoia) changed how often this consent is confirmed. During the 15.0 betas Apple described weekly prompts, then adjusted the shipping behavior; reports from that release describe a periodic re-prompt (widely described as monthly) and, for a while, a prompt associated with reboot. The exact cadence is OS behavior and can change in a point release. Context Assistant does not suppress it, and it does not request a restricted entitlement to skip it. When the prompt appears, the capture stops until the user allows it again.

Using `SCShareableContent` directly, instead of only `SCContentSharingPicker`, is a documented API. On recent systems it is also the path that can produce the extra "access your screen" confirmation because the app is choosing the window from the list the user already picked inside the app. The system picker is the other path this app offers. Both require the same Screen Recording grant. Neither is a bypass.

## App Sandbox, Hardened Runtime, signing, notarization

Each target is sandboxed through its entitlements file:

| Target | Sandbox | Extra entitlement |
| --- | --- | --- |
| Context Assistant | on | `com.apple.security.network.client`, so the model request can leave the machine |
| Capture Lab | on | none |
| Capture Diagnostics | on | `com.apple.security.files.user-selected.read-write`, so Save can write the JSON the user picks |

Screen Recording is not an entitlements key. Sandbox and TCC are separate. A sandboxed app still needs the user to allow Screen Recording. This repo does not add temporary exceptions, a library-validation disable, or a private mach-lookup exception.

Hardened Runtime is on for every target (`ENABLE_HARDENED_RUNTIME`). No exceptions are set.

For day-to-day work, Xcode Automatic signing with your Apple ID is enough. The TCC identity includes the signing identity, so changing from ad-hoc to a development certificate looks like a new app. Reset Screen Recording for the bundle id after that change.

Distribution outside your Mac needs Developer ID signing and notarization (`notarytool`, then stapling). This repo does not include a notarization script. Sandbox, Hardened Runtime, and a real signature are the inputs notarization expects. Notarization does not grant Screen Recording. The user still approves that on their Mac.

The API key is a keychain item (`kSecClassGenericPassword`, service `dev.codychen.ContextAssistant`, account `llm-api-key`, accessible when the device is unlocked). It is not in `UserDefaults`, Info.plist, or source. The sandbox uses the app's keychain. Console logs do not record the key or the OCR text.

## `sharingType = .none` and ScreenCaptureKit

Documented:

- AppKit still exposes `sharingType = .none` as "other processes should not get this window's content."
- The legacy window-image API documented that `kCGWindowSharingNone` windows are omitted.
- Apple's screen-capture sample excludes an app from a capture that app is performing by filtering it out of `SCContentFilter`, which is a different mechanism.

What is not safe to treat as a fact about a particular OS version:

- Public reports, including Apple Developer Forums thread 792152 (macOS 15.4), say a window set to `NSWindowSharingNone` was still present in a ScreenCaptureKit capture. A Developer Technical Support reply on that thread said there was no public API for preventing screen capture at that time, and asked for a Feedback request.
- A separate forums report describes the ScreenCaptureKit sample omitting a `NSWindowSharingNone` window at first, then including it after the filter is rebuilt. That is an inconsistency report, not a recipe, and this repo does not rebuild filters to chase content.
- Later SDKs may reword `.none` or ignore it. Read the header on the Xcode you actually have. Do not copy a blog's claim about a future SDK into a compatibility table.

What to measure, on your Mac, with your OS version in the JSON:

1. In Capture Lab, create two sample windows. Leave one at `.readOnly` and set the other to `.none`. Leave the main Capture Lab window at `.readOnly`.
2. In Capture Diagnostics, select one sample and run the probes.
3. Read `hasVisibleContent`, `success`, `error`, and `tccFailure` for `SCScreenshotManager.captureImage`, `SCScreenshotManager.captureSampleBuffer`, `SCStream`, and `CGWindowListCreateImage`.
4. Repeat for the other sample. Record `osVersion` with the result. A difference between macOS 14, 15, and 26 is a version-dependent observation. This repository does not publish a matrix and does not tell the assistant to switch APIs when a frame is blank.

Context Assistant's rule is the same on every version: one selected window, one ScreenCaptureKit still image, stop when the frame is near-black or the call fails.

## Blank frames

A protected, minimized, or fully covered window can come back as a black buffer, an empty buffer, or `SCFrameStatus.blank`. The assistant's heuristic, `FrameContent`, flags only near-black low-variance samples. A white empty document stays "visible" and then fails later, honestly, if Vision finds no text. That is a different outcome from a black frame, and neither outcome starts a second capture API.

## References

- AppKit: `NSWindow.sharingType`, `NSWindow.SharingType`
- ScreenCaptureKit: `SCShareableContent`, `SCContentFilter`, `SCStream`, `SCScreenshotManager`, `SCContentSharingPicker`
- Core Graphics: `CGWindowListCreateImage` (deprecated in macOS 14), `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`
- WWDC 2022 session 10156 and WWDC 2023 session 10136, "What's new in ScreenCaptureKit"
- macOS 15 release notes on deprecated capture APIs and migration to ScreenCaptureKit and `SCContentSharingPicker`
- Apple Developer Forums 792152, on `NSWindowSharingNone` and ScreenCaptureKit in macOS 15.4
