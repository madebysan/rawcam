<p align="center">
  <img src="assets/app-icon.png" width="128" height="128" alt="RawCam app icon">
</p>
<h1 align="center">RawCam</h1>
<p align="center">No AI. Just your sensor.<br>
An iOS camera that captures unprocessed RAW DNG files — bypassing Smart HDR, Deep Fusion, Night Mode, and Apple's entire computational photography pipeline.</p>
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

## Compared to other RAW camera apps

If you want a polished, production-ready RAW camera, use one of these — they're genuinely good:

| App | Price | What it does better than RawCam |
|-----|-------|----------------------------------|
| [Halide](https://halide.cam) | $36 one-time / $10/yr | Process Zero, manual focus, focus peaking, zebra stripes, ProRAW, waveform — the category benchmark |
| [ProCamera](https://www.procamera-app.com) | $8.99 one-time | Full manual controls, RAW burst, exposure bracketing, lens switching |
| [Moment Pro Camera](https://www.shopmoment.com/apps) | $9.99 one-time | Best for video, Apple Log, ProRes, 10-bit, great for filmmakers |
| [Not Boring Camera](https://notbor.ing/products/camera) | $15/yr | The best-designed camera app on iOS, film aesthetics baked in at capture |
| [Zerocam](https://zerocam.app) | $13/yr | Even simpler UI, strong anti-AI brand positioning |

RawCam doesn't compete with any of them on features. It exists for a different reason: it's **open source**, requires no account, costs nothing, and does exactly one thing — gets RAW DNG files off your sensor with no AI processing and no friction.

It's barebones by design. Think of it less as a camera app and more as a reference implementation: here's the minimum code needed to capture unprocessed RAW on iOS.

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
