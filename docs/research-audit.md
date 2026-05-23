# RawCam Research Audit

Updated: 2026-05-23

## Goal

Find features and improvements that fit RawCam's actual wedge: a minimal, private, open-source iPhone camera that saves unprocessed DNG files without pretending to be a full pro camera suite.

## Current App Snapshot

RawCam v1.0 is live on the App Store. The shipped public promise is narrow:

- RAW DNG capture
- RAW+JPG comparison mode
- Tap to focus
- Long-press AF/AE lock
- Flash off/on/auto
- Front/back camera switch
- Live 8-bar histogram
- No accounts, analytics, tracking, ads, or network requests

The codebase also contains partial manual exposure and white-balance work:

- `RawCam/CameraManager.swift` has ISO, shutter speed, white-balance presets, and Kelvin controls.
- `RawCam/CameraView.swift` has `exposurePanel` and `wbPanel` views.
- Those panels are not mounted in the visible UI.
- The help sheet mentions tapping a yellow AF/AE badge in a panel to unlock, but no visible panel or badge is currently exposed.

That makes the first v1.1 candidate obvious: either expose those controls cleanly, or remove/update the unreachable copy and unused UI code.

## Market Findings

### 1. "No AI" has become a real camera-app lane

Halide's Process Zero positioning is close to RawCam's premise: minimal processing, no AI, and a single-shot RAW-based workflow. Halide adds an Image Lab for later re-development and frames the look honestly as darker, grainier, and more deliberate than Apple's default output.

Implication for RawCam: the wedge is valid, but the app should stay blunt and clear. RawCam should not try to out-Halide Halide. It should be the free, open-source, no-network DNG button with just enough capture aids to avoid bad files.

Sources:

- [Halide product page](https://halide.cam/)
- [Process Zero manual](https://www.lux.camera/process-zero-manual/)
- [TechCrunch on Halide Process Zero](https://techcrunch.com/2024/08/14/camera-app-halides-latest-update-adds-an-option-for-zero-ai-image-processing/)

### 2. Pro tools cluster around exposure and focus aids

Halide emphasizes zebras, waveforms, histograms, focus peaking, focus loupe, manual mode, white balance, metadata, and custom processing choice. ProCamera lists independent focus/exposure, manual mode, focus peaking, zebra stripes, manual white balance, RAW/ProRAW/TIFF/JPG/HEIF, live histogram, aspect ratios, anti-shake, self timer, and metadata tools.

Implication for RawCam: the best additions are not more formats. They are small capture aids that help a user make a better DNG before opening Lightroom or Darkroom.

Sources:

- [Halide product page](https://halide.cam/)
- [ProCamera App Store listing](https://apps.apple.com/us/app/procamera/id694647259)
- [ProCamera features page](https://www.procamera-app.com/en/features/)

### 3. 48 MP is tempting, but it cuts against RawCam's core promise

Apple says ProRAW combines standard RAW information with iPhone image processing. Apple also documents that 48 MP ProRAW is limited to iPhone 14 Pro and later Pro models, only on the main 1x camera, and falls back depending on zoom, Night mode, flash, and macro conditions.

Implication for RawCam: a 48 MP/ProRAW mode should not be the default roadmap. If added later, it should be labeled as "Apple ProRAW" or "processed RAW comparison," not treated as the same thing as RawCam's sensor-pure DNG mode.

Source:

- [Apple Support: About Apple ProRAW](https://support.apple.com/en-us/119916)

### 4. Hardware launch and shutter shortcuts are now table stakes for camera apps

iOS 18 opened more third-party camera entry points through Lock Screen/Control Center/Action Button flows, and Apple exposes capture hardware button handling through `AVCaptureEventInteraction`. Halide and Obscura have already marketed Lock Screen and Camera Control support.

Implication for RawCam: this is worth investigating after the core capture UI is clean. It fits the "minimal camera" promise because it reduces friction instead of adding clutter.

Sources:

- [Apple Developer: AVCaptureEventInteraction](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction)
- [Apple Support: use Camera Control to open another app](https://support.apple.com/guide/iphone/use-the-camera-control-to-open-another-app-iph3940f00d2/ios)
- [MacRumors: iOS 18 third-party camera Lock Screen access](https://www.macrumors.com/2024/06/12/ios-18-activate-camera-app-lock-screen/)

## Recommended Feature Roadmap

### P0: Fix the half-shipped controls

Expose or remove the existing manual exposure and white-balance panels.

Best version:

- A compact controls drawer above the shutter.
- One row for AF/AE lock state and unlock.
- One row for exposure: Auto/Manual, ISO, shutter.
- One row for WB: Auto, Daylight, Cloudy, Tungsten, Fluorescent, Kelvin.
- Keep default state collapsed so the app still opens as a simple camera.

Why first:

- The code is already partly there.
- It fixes the help-sheet mismatch.
- It moves RawCam from "barebones" to "minimal but serious."

### P1: Clipping warnings

Add highlight and shadow clipping indicators tied to the live histogram.

Options:

- Keep the current 8-bar histogram, but tint the first/last bar when clipping.
- Add optional zebra overlay for highlights.
- Add a small `CLIP` badge when either edge is overloaded.

Why it fits:

- RAW users care about preserving recoverable data.
- This is simpler than a full waveform.
- It avoids adding editing features.

### P1: Grid and level

Add a rule-of-thirds grid and horizon level toggle.

Why it fits:

- Low visual complexity.
- Common expectation in camera apps.
- Helps composition without changing RawCam's file promise.

### P1: Lens selector with honest availability

Add `.5x`, `1x`, `2x/3x/5x` options where the device supports them, but disable or explain choices that cannot produce RAW.

Why it fits:

- Users expect lens choice on modern iPhones.
- It needs careful messaging because RAW support varies by device and lens.
- It should never silently switch away from a true RAW-capable capture path.

### P2: Focus assist

Add a manual focus mode with either:

- focus loupe, first
- focus peaking, second

Why not first:

- It is more UI and image-processing work than clipping/grid.
- It risks turning RawCam into a Halide clone if overbuilt.

### P2: Capture workflow polish

Improve the moments around capture and saving:

- clearer saving state
- clearer RAW unsupported message per lens/device
- optional self-timer
- optional volume-button shutter
- latest photo handoff that opens the actual saved asset when possible

### P3: Camera Control / Lock Screen support

Investigate iOS 18+ Lock Screen capture extension and hardware button support.

Good outcome:

- RawCam can launch quickly from Lock Screen/Camera Control.
- Hardware capture triggers the shutter.

Risk:

- More entitlement/API complexity.
- Needs real-device testing on compatible hardware.

### P3: Apple ProRAW comparison mode

Only consider this as an explicit comparison mode:

- `RAW`
- `RAW+JPG`
- `Apple ProRAW`, clearly labeled as processed

Do not make this the headline feature unless RawCam's positioning changes.

## Improvements Outside The App UI

### App Store screenshots

The existing backlog item is correct. Improve screenshots around the real wedge:

- one strong hero capture
- one labeled UI shot: histogram, focus lock, RAW mode
- one honest RAW vs Apple-processed comparison
- one privacy/no-network card if Apple allows it without looking like filler

### README cleanup

The README currently uses a centered hero and horizontal dividers. san's current README convention is left-aligned with no centered hero block and no divider between hero and body. This is not a product feature, but it should be cleaned up before the next GitHub push.

### Metadata update after controls are exposed

If manual controls ship, update:

- README feature list
- App Store description
- release notes
- support FAQ

Do not advertise manual exposure or white balance until the visible UI actually exposes them.

## Do Not Build Yet

- In-app RAW editor. This fights the "bring your own editor" promise.
- Filters or film looks. That belongs in the editor, not RawCam.
- Social sharing or accounts. It breaks the privacy story.
- Video. It is a different product with storage, thermal, audio, dropped-frame, and external-drive concerns.
- A full Halide-style pro interface. RawCam wins by being smaller.

## Decision

Build v1.1 around capture confidence, not feature count:

1. Expose the existing manual exposure/WB work or remove the dead paths.
2. Add clipping warnings.
3. Add grid and level.
4. Add lens selection only if RAW support can be shown honestly per device.

That gives RawCam a clear next version without blurring its identity.
