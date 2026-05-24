# RawCam Video Handoff - 2026-05-24

## What changed
- Added the video capture sequence through Phase 4: capability audit, basic HEVC recording, format cycling, RawCam roll indexing, and reliability hardening.
- Updated the camera UI so video mode hides photo-only controls and uses `ZEBRA / FORMAT / AUDIO` in one row.
- Changed the library button into an in-app RawCam roll for captures made by the app.
- Added pinch-to-zoom, promoted lens zoom selection into the main UI, and moved photo format into the controls drawer.
- Added `HELP / STATUS / RESET` as secondary actions.
- Added photo `ASPECT` framing guides, photo `STEADY` capture delay, and video `AUDIO` mic toggling.

## Commits from this session
- `d2d22b1` Add basic HEVC video recording
- `84fc32c` Add capability based video formats
- `eab0153` Harden video recording lifecycle
- `3735f14` Polish video controls and roll playback
- `f1d282b` Promote lens zoom and simplify format controls
- `3e75b48` Hand off roll videos to Photos
- `2b3c888` Separate secondary controls
- `8925765` Add status, steady, aspect, and audio controls
- `991488e` Place video audio control beside format

## Verification
- Generic iOS builds passed after the final UI changes.
- Connected iPhone Debug build passed.
- App installed on the connected iPhone.
- App launched on the connected iPhone.

## Known limits
- Exact Photos asset handoff from the RawCam roll is not reliable with the current add-only Photos permission model. The app can open Photos, but iOS does not guarantee focus on the tapped asset.
- `ASPECT` is a framing guide, not an output crop.
- `STEADY` waits briefly for motion steadiness before capture.
- `AUDIO` must be set before recording starts.

## Next QA pass
- Test RawCam roll empty state, image thumbnails, RAW+JPG thumbnails, bracket entries, video thumbnails, and image/video Photos handoff.
- Collect `Debug/video-capabilities.txt` from app support.
- Test video recording on device: microphone prompt, silent fallback, start/stop, elapsed timer, Photos save, format cycling, roll entry, lens switching before recording, backgrounding, audio interruptions, low storage, thermal/system pressure, and returning to photo capture.
- Test new controls: `STATUS`, `ASPECT`, `STEADY`, `AUDIO`, pinch-to-zoom, lens zoom selector, and reset all.
- Decide whether Phase 3 manual video controls should ship before or after release hardening.
