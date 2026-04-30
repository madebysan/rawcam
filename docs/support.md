# RawCam Support

A minimal camera that saves only the sensor's raw DNG. No AI postprocessing.

## Contact

Email: [snt.aln@gmail.com](mailto:snt.aln@gmail.com)

I read every email. Bug reports, feature requests, and general feedback are all welcome.

## Frequently asked questions

### What is a DNG file and why does RawCam save them?

DNG (Digital Negative) is Adobe's open RAW format. It contains the unprocessed data from the camera sensor, before any sharpening, noise reduction, tone mapping, or color science is applied. Standard JPEGs from the Camera app have all of that baked in and unrecoverable. A DNG gives you the room to make those decisions yourself in an editor like Lightroom, Capture One, Darkroom, or Photoshop.

### How do I open a DNG file?

Apple's Photos app can preview DNGs but won't show their full dynamic range. Open them in Lightroom, Lightroom Mobile, Darkroom, Capture One, or any other RAW editor to actually edit them.

### Where do my photos save?

To your iPhone's photo library, the same place the regular Camera app saves to. Photos are stored as DNG files. In RAW+JPG mode, RawCam saves both a DNG and a JPEG as two separate photos.

### What's the difference between RAW and RAW+JPG mode?

- **RAW**: saves only the DNG. Smaller storage footprint, no Apple processing at all.
- **RAW+JPG**: saves both a DNG and a JPEG of the same shot. Useful for comparing what the stock pipeline does to a scene, or for quickly sharing a JPEG while keeping the DNG to edit later.

### How do I focus on something specific?

Tap anywhere on the preview to focus there. The reticle shows where the camera is focused. Long-press to lock both autofocus and auto-exposure on that point — useful when you want to recompose without the exposure shifting.

### Why is the resolution 12 megapixels and not 48?

Apple caps third-party RAW capture at 12MP on iPhone. The 48MP full sensor readout is reserved for Apple's own camera pipeline. Every third-party camera app hits the same ceiling — that's an iPhone hardware/software limitation, not a RawCam limitation.

### What does the histogram show?

An 8-bar readout from shadows on the left to highlights on the right. Tall bars on either edge mean detail is being clipped (lost) at that end of the tonal range. A balanced histogram across the middle is generally a healthy exposure.

### Why does my photo look darker or flatter than the Camera app?

Because RawCam isn't doing anything to it. The Camera app brightens shadows, recovers highlights, sharpens edges, and reduces noise — all automatically. A DNG looks "flat" by design. That flatness is dynamic range you can recover in editing. Adjust exposure, contrast, and shadows in your RAW editor to taste.

### Can I switch between front and back cameras?

Yes. Tap the camera switch icon. Both front and back cameras capture in DNG.

### Does the flash work?

Yes. Three modes: Off, On, and Auto.

### Does RawCam upload my photos anywhere?

No. RawCam has no servers, no accounts, and makes no network requests. Photos save to your iPhone's photo library and never leave your device unless you choose to share them yourself.

### Why don't I see my DNG photo in the iOS Photos app?

You should — DNGs appear alongside JPEGs in the standard photo library. If a photo is missing, make sure you granted RawCam permission to save to your photo library when you first opened the app. You can check this in the iOS Settings app: Settings → Privacy & Security → Photos → RawCam.

### Can I shoot video with RawCam?

Not in v1. RawCam is photos only. Video may come later.

## Reporting bugs

The fastest way is email. Include:

1. What you were trying to do
2. What happened instead
3. Your iPhone model and iOS version
4. A screenshot if relevant

## Privacy and data

See the [full privacy policy](privacy-policy.md). Short version: RawCam doesn't collect anything. Photos save to your device.
