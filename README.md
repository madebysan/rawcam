<img src="assets/app-icon.png" width="128" height="128" alt="RawCam app icon">

# RawCam

A minimal iOS camera. Saves only the sensor's raw DNG.

**v1.0** · iOS 17+

<a href="https://apps.apple.com/us/app/rawcam-raw-dng-camera/id6765531876">
  <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
</a>

![RawCam interface, info panel, and a side-by-side comparison of the same scene captured with RawCam and the iOS Camera app](assets/screenshot.png)

RawCam is a minimal iOS camera that saves only the sensor's raw DNG. Tap the shutter, open the file in Lightroom or any RAW editor, and process it yourself.

## What it does

- **RAW mode.** Saves a single 12MP DNG with zero AI processing.
- **RAW+JPG mode.** Captures both a clean DNG and an Apple-processed JPEG simultaneously (saved as two photos). Useful for comparing what the stock pipeline does to a shot.
- **Tap to focus.** Tap anywhere on preview. Long-press to lock AF + AE.
- **Manual exposure.** Toggle manual mode for ISO and shutter speed.
- **EV compensation.** Adjust auto exposure without switching to full manual.
- **Separate metering.** Switch tap mode between focus and exposure targeting.
- **White balance controls.** Use auto, daylight, cloudy, tungsten, fluorescent, or Kelvin.
- **Lens selector.** Switch supported rear lenses and see RAW availability honestly.
- **Grid + level.** Optional composition grid and horizon level.
- **Focus aids.** Focus loupe and optional focus peaking for sharper manual checks.
- **Self-timer.** Off / 3s / 10s.
- **Volume-button shutter.** Use the hardware volume buttons as a shutter release.
- **Anti-shake shutter.** Waits for the phone to steady before firing.
- **RAW bracketing.** Captures three RAW frames at different EV values.
- **Last-shot details.** Shows mode, lens, ISO, shutter, EV, white balance, and clipping.
- **App Shortcut.** Launch RawCam from Shortcuts, Siri, Spotlight, or the Action Button on supported iPhones.
- **Flash toggle.** Off / on / auto.
- **Front / back camera** switch.
- **Live histogram.** 8-bar readout with highlight/shadow clipping warnings.

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

RawCam stays focused on clean DNG capture. If you need ProRAW processing, video, film looks, or a full editing lab, use [Halide](https://halide.cam), [ProCamera](https://www.procamera-app.com), or [Not Boring Camera](https://notbor.ing/products/camera). All three are good.

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
