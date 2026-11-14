# Glance

A macOS 14+ study tool. You pick one window. A global shortcut captures that window with ScreenCaptureKit, reads the text with Vision, and streams an answer into a floating panel. The panel stays visible to screenshots and screen sharing.

Capture Lab and Capture Diagnostics are separate apps for measuring how public window and capture APIs behave on your Mac. They are described in [RESEARCH.md](RESEARCH.md). The module map, actors, cancellation, and memory limits are in [ARCHITECTURE.md](ARCHITECTURE.md).

Owner: Cody Chen.

## What was verified here

`Packages/GlanceCore` was built and tested on Linux with Swift 6.2.4 (`swift test` in that directory). **44 tests passed, 0 failed.** They cover hashing, similarity, the blank-frame heuristic, capture sizing, the token bucket, the response cache, the SSE parser, prompt building, history trimming, capture policy, the diagnostics JSON shape, and the chat client through a `URLProtocol` mock.

On macOS the client streams with `URLSession.bytes(for:)`. swift-corelibs-foundation 6.2 does not implement `bytes(for:)`, so the Linux build reads `URLSession.data(for:)` and splits lines. The parser and the request body are the same on both.

The three apps were not compiled here. This machine has no Xcode and no AppKit, ScreenCaptureKit, or Vision SDK. Names were checked against Apple's macOS 14 ScreenCaptureKit surface (`SCContentSharingPicker.add`, `present(using:)`, `SCContentFilter(desktopIndependentWindow:)`, `contentRect`, `pointPixelScale`, `SCScreenshotManager.captureImage` and `captureSampleBuffer`, `SCStream`). If a newer SDK renames one of those Swift overlays, the error will point at `Shared/MacCapture` or `CaptureDiagnostics/CaptureProbes.swift`. `CGWindowListCreateImage` is resolved with `dlsym` so a missing declaration does not break the build.

## Requirements

- macOS 14 or later
- Xcode 15 or later (a current Xcode that includes the macOS 14+ SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An OpenAI-compatible chat endpoint, or a local one such as Ollama or LM Studio at a `/v1` base URL

Swift 5.9 language mode is set in `project.yml` and in the package. Strict concurrency checking is on. A Swift 6 toolchain accepts that mode.

## Generate the project and run

From the repo root:

```bash
xcodegen generate
open GlanceSuite.xcodeproj
```

In Xcode, select your team on each app target (Signing & Capabilities). The entitlements files already enable the App Sandbox and Hardened Runtime. Glance also has outgoing network. Capture Diagnostics can save a file you pick. Do not turn Hardened Runtime off and do not add an entitlement that disables library validation.

Run one scheme at a time:

| Scheme | What it is |
| --- | --- |
| Glance | The assistant. Bundle id `dev.codychen.Glance` |
| Capture Lab | Your own test windows. Bundle id `dev.codychen.CaptureLab` |
| Capture Diagnostics | JSON probes. Bundle id `dev.codychen.CaptureDiagnostics` |

The first build resolves the local package `Packages/GlanceCore`.

## Grant Screen Recording

Glance and Capture Diagnostics need Screen Recording. Capture Lab does not capture anything.

1. Launch the app.
2. Click **Request access**, or **Open Settings** and enable the app under Privacy & Security → Screen Recording.
3. If the toggle does not take effect, quit the app and open it again.
4. Click **Refresh windows** and select one row, or use **System picker** and confirm one window.

macOS 15 and later can ask again on a timer. That dialog is the system's. The app does not skip it. Details are in RESEARCH.md.

The prompt text comes from `NSScreenCaptureUsageDescription` in each app's Info.plist.

Reset a bad grant:

```bash
tccutil reset ScreenCapture dev.codychen.Glance
tccutil reset ScreenCapture dev.codychen.CaptureDiagnostics
```

## Set the API key

The key is stored in the login keychain by the Security framework. It is not written to UserDefaults, the plist, or the repo.

1. Open Glance.
2. Paste the key into the secure field.
3. Click **Save to Keychain**. The field is cleared. The window then says a key is stored.
4. Set **Base URL** to the API root, for example `https://api.openai.com/v1` or `http://127.0.0.1:11434/v1`.
5. Set **Model** to the name that server expects. The default is `gpt-4o-mini`.

A local server on `localhost`, `127.0.0.1`, or `::1` may be used with an empty key. Any other `http://` URL shows a warning. Remove the key with **Remove key**.

## Use the assistant

1. Select a window.
2. Edit the question, or leave the default.
3. Press the global shortcut (Control-Option-Space until you change it) or click **Ask**.

The floating panel is an `NSPanel`: non-activating, floating, and joined to all spaces, including full screen. `sharingType` is `.readOnly`. There is no control that changes it.

While a capture is in progress the dot in the panel is orange and the menu bar icon changes. Escape or **Stop** cancels the in-flight request. A new Ask cancels the previous one.

**Again** skips the cache and the "text did not change" check. Command-[ and Command-] move through saved answers. The opacity slider stops at 55%. Position presets move the panel; you can still drag it.

Conversation history is a trimmed JSON file in Application Support (`Glance/history.json` inside the sandbox container). The model sees a bounded excerpt, not the image.

## Capture Lab and Capture Diagnostics

1. Run Capture Lab and create one or two sample windows. The stripes and the sentence "If you can read this sentence, the frame is not blank." are the visible content.
2. Set `sharingType` to `.readOnly` or `.none` on a **sample** window. The main Capture Lab window stays `.readOnly`. Level and collection behavior apply only to those sample windows.
3. Note the `windowNumber`.
4. Run Capture Diagnostics, select that window, and click **Run independent probes**.
5. Read the JSON. Each entry names the API, the window id, title, owner, the OS version, whether the call succeeded, whether the frame has non-uniform content, and any error or TCC failure. `usedAsFallback` is always false.

The report does not include pixels. Copy or Save writes that JSON only.

## Tests

Package tests (hashing, similarity, blank-frame inputs, token bucket, cache, SSE parser, prompts, history trimming, the streaming client through `URLProtocol`):

```bash
cd Packages/GlanceCore
swift test
```

In Xcode, the Glance scheme also runs `GlanceCoreTests` and `CaptureIntegrationTests`. The integration tests build as part of Glance so the Screen Recording grant matches that app. The pixel tests always run. The tests that call ScreenCaptureKit skip when `CGPreflightScreenCaptureAccess()` is false. To capture one window from the test:

```bash
CONTEXT_ASSISTANT_TEST_WINDOW_ID=1234
```

Set that in the scheme's environment. The test records the outcome, including a blank frame, and does not try a second API.

## Debug

Stream this app's logs:

```bash
log stream --predicate 'subsystem == "dev.codychen.Glance"' --level debug
```

Categories are `capture`, `llm`, `hotkey`, and `store`. Logs contain status text and error descriptions, not the API key and not the recognized text.

If the shortcut will not register, another app owns that combo. Pick a new one in the window. OSStatus is shown next to the control.

If Screen Recording is on and the window list is empty, confirm you launched the signed app from Xcode (not an old copy in `/Applications`) and reset TCC for the bundle id above.

A blank frame is reported in the panel and the pipeline stops. That includes a protected window. The assistant will not switch to `CGWindowListCreateImage` or open a stream to try again.

## Known limitations

- macOS apps in this repo were reviewed against Apple's public ScreenCaptureKit, Vision, AppKit, and Carbon APIs. They still have to be compiled in Xcode on a Mac. A newer SDK can rename a ScreenCaptureKit Swift overlay or drop the `CGWindowListCreateImage` declaration; diagnostics already resolve that symbol at runtime and record it when it is absent.
- `sharingType = .none` does not have one behavior across macOS 14, 15, and later. Measure it. Do not treat a single OS version as the rule. See RESEARCH.md.
- Vision OCR depends on contrast and font size. A blank capture and a capture with no readable text are different errors.
- The global shortcut works only while Glance is running. Carbon hotkeys need at least one modifier.
- The answer panel is visible to screen sharing on purpose.
- History and the response cache are local and size-capped. They are not encrypted beyond what the disk and keychain already provide. The key is the only secret, and it stays in the keychain.
- The apps are not notarized. Signing with your development team is enough to run them from Xcode.
- Sandbox plus a new signature can make an old keychain item or TCC grant look missing. Reset TCC and save the key again.
- Capture Diagnostics runs four probes so you can compare APIs. That comparison is the research tool. The assistant never does it.
