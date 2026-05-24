<p><img src="assets/app-icon.png" width="128" height="128" alt="RawCam app icon"></p>

<h1>RawCam</h1>

<p>A minimal iOS camera. Saves only the sensor's raw DNG.</p>

<p><strong>v1.1</strong> · iOS 17+</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-0066cc" alt="SwiftUI">
  <img src="https://img.shields.io/badge/iOS-000000" alt="iOS">
</p>

<p>
  <a href="https://apps.apple.com/us/app/rawcam-raw-dng-camera/id6765531876"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50"></a>
</p>

![RawCam interface, info panel, and a side-by-side comparison of the same scene captured with RawCam and the iOS Camera app](assets/screenshot.png)

RawCam is a minimal iOS camera that saves only the sensor's raw DNG. Tap the shutter, open the file in Lightroom or any RAW editor, and process it yourself.

## What it does

- **RAW mode.** Saves a single 12MP DNG with zero AI processing.
- **RAW+JPG mode.** Captures both a clean DNG and an Apple-processed JPEG simultaneously (saved as two photos). Useful for comparing what the stock pipeline does to a shot.
- **3x3 tools grid.** Exposure, white balance, lens, lock, timer, grid, level, tap targeting, and bracketing in one compact drawer.
- **Tap to focus.** Tap anywhere on preview. Use `LOCK` to hold current AF/AE, or long-press for point-based focus lock.
- **Manual exposure.** Toggle manual mode for ISO and shutter speed.
- **EV compensation.** Adjust auto exposure without switching to full manual.
- **Separate metering.** Switch tap mode between focus and exposure targeting.
- **White balance controls.** Use auto, daylight, cloudy, tungsten, fluorescent, or Kelvin.
- **Lens selector.** Switch supported rear lenses and see RAW availability honestly.
- **Grid + level.** Optional composition grid and horizon level.
- **Self-timer.** Off / 3s / 10s.
- **Volume-button shutter.** Use the hardware volume buttons as a shutter release.
- **RAW bracketing.** Captures three RAW frames at different EV values.
- **Last-shot details.** Shows mode, lens, ISO, shutter, EV, white balance, clipping, and a preview when available.
- **RawCam roll.** Opens recent RawCam captures in-app with preview thumbnails and capture details, without browsing your full Photos library.
- **Basic video mode.** Records simple HEVC video to Photos with a minimal record button and elapsed timer.
- **App Shortcut.** Launch RawCam from Shortcuts, Siri, Spotlight, or the Action Button on supported iPhones.
- **Flash toggle.** Off / on / auto.
- **Front / back camera** switch.
- **Live histogram + zebra.** Orange edge bars mark clipping, and zebra stripes warn when highlights blow out.

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

- **12MP cap.** iOS caps third-party RAW capture at 12MP. The 48MP full sensor readout is locked to Apple's own camera pipeline, so any third-party app hits the same ceiling.

## Alternatives

RawCam stays focused on clean capture. If you need ProRAW processing, advanced video formats, film looks, or a full editing lab, use [Halide](https://halide.cam), [ProCamera](https://www.procamera-app.com), or [Not Boring Camera](https://notbor.ing/products/camera). All three are good.

RawCam is the free, open-source version that does one thing.

## Stack

- Swift + SwiftUI + AVFoundation + Photos
- No dependencies, no packages

## Feedback

Found a bug or have a feature idea? See the [support page](docs/support.md) for FAQs and contact info, or [open an issue](https://github.com/madebysan/rawcam/issues).

## License

[MIT](LICENSE)

---

Made by [santiagoalonso.com](https://santiagoalonso.com)
