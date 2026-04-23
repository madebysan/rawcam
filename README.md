<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="RawCam app icon">
</p>
<h1 align="center">RawCam</h1>
<p align="center">A minimal, open-source iOS camera app. No AI postprocessing. Just your sensor.<br>
No Smart HDR, no Deep Fusion, no Night Mode, no noise reduction, no sharpening.<br>
Open the DNG in Lightroom or Darkroom and get 2–3 extra stops of recovery the JPEG never had.</p>
<p align="center"><strong>v0.2</strong> · iOS 17+ · Requires Xcode to build</p>
<p align="center"><a href="#how-to-build--install"><strong>Build & Install →</strong></a></p>

---

## What it does

- **RAW mode** — saves a single 12MP DNG with zero AI processing
- **RAW+JPG mode** — captures both a clean DNG and an Apple-processed JPEG simultaneously (saved as 2 photos), useful for comparing what Apple's pipeline does to a shot
- **Tap to focus** — tap anywhere on preview; long-press to lock AF + AE
- **Flash toggle** — off / on / auto
- **Front/back camera** switch
- **Live histogram** — 8-bar readout, shadows to highlights

---

## How to build & install

Requires Xcode 15+ and an iPhone connected via USB.

```bash
# Build
xcodebuild -project RawCam.xcodeproj -scheme RawCam \
  -destination 'id=<YOUR_DEVICE_ID>' \
  -allowProvisioningUpdates build

# Install
xcrun devicectl device install app \
  --device <YOUR_DEVICE_ID> \
  /path/to/DerivedData/RawCam.../RawCam.app
```

Find your device ID:
```bash
xcrun xctrace list devices
```

Bundle ID: `com.santiagoalonso.rawcam`
Minimum iOS: 17.0

> **Signing:** Open `RawCam.xcodeproj` in Xcode, select the RawCam target → Signing & Capabilities → change the Team to your own Apple Developer account.

---

## Why not just use the iOS Camera app?

The stock Camera app always applies an irreversible AI pipeline (Smart HDR, Deep Fusion, tone mapping, etc.) before saving. Once applied, the original sensor data is gone. RawCam skips all of that — what the sensor captured is what you get.

Adobe Lightroom's free camera also captures RAW DNG, but it requires an Adobe account and is buried inside an editing app. RawCam is a single-purpose camera with no account needed.

**Limitation:** iOS caps third-party RAW capture at 12MP. The 48MP full sensor readout is locked to Apple's own camera pipeline.

---

## Alternatives

RawCam is intentionally barebones. If you want manual controls, focus peaking, ProRAW, or a polished UI, you'll be better served by [Halide](https://halide.cam), [ProCamera](https://www.procamera-app.com), or [Not Boring Camera](https://notbor.ing/products/camera) — they're all genuinely good.

RawCam exists for a different reason: it's open source, costs nothing, and does exactly one thing.

---

## Stack

- Swift + SwiftUI + AVFoundation + Photos
- No dependencies, no packages

---

## Feedback

Found a bug or have a feature idea? [Open an issue](https://github.com/madebysan/rawcam/issues).

## License

[MIT](LICENSE)

---

Made by [santiagoalonso.com](https://santiagoalonso.com)
