<p><img src="assets/app-icon.png" width="128" height="128" alt="RawCam app icon"></p>

<h1>RawCam</h1>

<p>Shoot unprocessed DNG photos on your iPhone.<br>
Keep the sensor data, then decide the sharpening, color, and contrast yourself.</p>

<p><strong>Version 1.1</strong> · iOS 17+</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-0066cc" alt="SwiftUI">
  <img src="https://img.shields.io/badge/iOS-000000" alt="iOS">
</p>

<p>
  <a href="https://apps.apple.com/us/app/rawcam-raw-dng-camera/id6765531876"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50"></a>
</p>

![RawCam interface, info panel, and a side-by-side comparison of the same scene captured with RawCam and the iOS Camera app](assets/screenshot.png)

RawCam saves the photo file before the iPhone Camera app has made its own processing decisions. Shoot a DNG, open it in Lightroom, Capture One, Darkroom, or another RAW editor, and decide how much sharpening, denoising, color, and contrast you want.

## What RawCam captures

- **RAW photos.** RAW mode saves a single 12MP DNG. RAW+JPG saves the DNG and an Apple-processed JPEG as two separate photos, which makes it easy to compare RawCam against the stock pipeline.
- **Manual controls.** The controls drawer has `EXP`, `WB`, `LENS`, `LOCK`, `TAP`, `FORMAT`, `TIMER`, and `BRKT` controls for ISO, shutter speed, EV compensation, white balance presets, Kelvin adjustment, rear lens selection, AF/AE lock, separate focus/exposure targeting, RAW+JPG switching, self-timer, and three-shot RAW bracketing.
- **Framing and capture aids.** Pinch-to-zoom, quick lens zoom, grid, horizon level, aspect guides, steady capture delay, hardware volume shutter, flash modes, and front/back camera switching are all built into the capture screen.
- **Exposure warnings.** The live histogram marks clipped shadows or highlights with orange edge bars. Zebra stripes warn when highlights are blowing out.
- **Last-shot details.** After a capture, RawCam can show the saved mode, lens, ISO, shutter, EV, white balance, clipping state, and a preview when one is available.
- **RawCam roll.** The in-app roll shows recent photos and videos captured by RawCam, with thumbnails and capture details, without browsing your full Photos library.
- **Video.** Video mode records HEVC clips to Photos with an elapsed timer. The `FORMAT` control exposes HDR, Log, ProRes, or ProRes Log only when the current device and session support them. `AUDIO` lets you record with or without microphone audio.
- **Shortcuts and utility controls.** RawCam includes an App Shortcut for Shortcuts, Siri, Spotlight, and the Action Button. `HELP`, `STATUS`, and `RESET` sit outside the main capture grid so the shooting controls stay focused.

## Why not just use the iOS Camera app?

The stock Camera app runs every shot through an AI pipeline: Smart HDR, Deep Fusion, tone mapping, noise reduction, sharpening. Once applied, the original sensor data is gone. In dynamic range or low light, that's 2–3 stops of recovery baked out of the JPEG you can never get back. RawCam saves the DNG before any of that happens.

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

## Known limitations

- **12MP RAW cap.** iOS caps third-party RAW capture at 12MP. The 48MP full sensor readout is locked to Apple's own camera pipeline, so any third-party app hits the same ceiling.
- **RawCam roll scope.** The in-app roll indexes captures made by RawCam from this version forward. It uses add-only Photos access, so it does not read your full photo library.

## Alternatives

RawCam stays focused on clean capture. If you need ProRAW processing, a deeper video suite, film looks, or a full editing lab, use [Halide](https://halide.cam) or [ProCamera](https://www.procamera-app.com).

RawCam is the free, open-source version that does one thing.

## Stack

- Swift + SwiftUI + AVFoundation + Photos
- No dependencies, no packages

## Feedback

Found a bug or have a feature idea? See the [support page](docs/support.md) for FAQs and contact info, or [open an issue](https://github.com/madebysan/rawcam/issues).

## License

[MIT](LICENSE)

Made by [santiagoalonso.com](https://santiagoalonso.com)
