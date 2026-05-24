# Changelog

All notable shipped features and changes, organized by date.
Updated every session via `/save-session`.

---

## 2026-05-24

### Features
- **Video capture sequence:** added Debug capability reporting, basic HEVC recording, format cycling, RawCam roll entries for videos, and lifecycle hardening for interruptions, backgrounding, storage, and pressure events.
- **Video controls:** added video mode with elapsed recording state, hidden photo-only controls, `ZEBRA / FORMAT / AUDIO` in one row, and a microphone toggle that controls whether audio is attached before recording.
- **In-app media roll:** changed the photo-library button into a RawCam roll for captures made in the app, with image/video previews and Photos handoff for tapped media.
- **Camera control polish:** moved photo format into the controls drawer, promoted lens zoom selection into the main camera UI, added pinch-to-zoom, and added reset-all behavior.
- **Photo controls:** added `ASPECT` framing guides and `STEADY` capture delay for handheld shots.
- **Secondary actions:** separated `HELP`, `STATUS`, and `RESET` from the main control grid.

### Build
- Built, installed, and launched the latest Debug build on the connected iPhone.
- Prepared App Store metadata and reviewer notes for the video-enabled build and bumped the build number to `1.1 (3)`.

### Status: local QA build ready

---

## 2026-05-23

### Features
- **Manual controls drawer:** shipped a 3x3 tools grid with manual exposure, white balance, lens selection, AF/AE lock, self-timer, grid, level, tap targeting, and RAW bracketing.
- **Capture aids:** added horizon level, self-timer, EV compensation, separate focus/exposure targeting, and zebra warnings.
- **Shooting workflow:** added three-shot RAW bracketing, volume-button shutter, a last-shot details panel, and an App Shortcut for Shortcuts/Siri/Spotlight/Action Button launch.
- **Competitor parity batch:** added lens selection, volume-button shutter, persistent settings, a last-shot session strip, and an App Shortcut for Shortcuts/Siri/Action Button launch.
- **Focus peaking rollback:** removed the first focus-peaking implementation after real-device testing showed it could destabilize the camera UI.
- **Focus lock stabilization:** removed the duplicate live preview loupe and changed long-press to focus-only lock so it cannot black out the preview by hard-locking exposure.
- **Histogram clipping warning:** replaced the `CLIP` badge with orange edge bars inside the histogram, plus zebra stripes when highlights clip.
- **Info sheet refresh:** shortened the in-app help sheet, made cards full-width, linked the footer credit, and synced icons with the live controls.
- **Control design polish:** applied a Not Boring-inspired pass to the camera controls with amber identity color, icon/readout chips, dimensional active states, a richer drawer surface, and a more instrument-like shutter.
- **Collapsible tools drawer:** moved the control toggle into the shutter row beside the photo thumbnail. Tap it or swipe up to reveal controls, then tap again or swipe down to hide them and restore preview space.

### Docs
- **Feature copy:** updated README, support docs, backlog, and App Store metadata for the new capture controls.

### Status: v1.1 build 2 submitted for App Review

---

## 2026-05-01 (session 2)

### Features
- **App Store live** — RawCam v1.0 approved and available at https://apps.apple.com/us/app/rawcam-raw-dng-camera/id6765531876

### Docs
- **README badge** — replaced "In App Store review" status with the official Download on the App Store badge, matching the Arrival README pattern

### Status: shipped (live on App Store)

---

## 2026-04-30 (session 1)

### Features
- **App Store submission** — RawCam v1.0 submitted to Apple Review. State: WAITING_FOR_REVIEW. Auto-release on, app goes live ~30 min after approval.

### Build
- **Encryption compliance** — added `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` to Debug + Release configs
- **iPhone-only** — switched `TARGETED_DEVICE_FAMILY` from `"1,2"` to `"1"` to reduce iPad review surface
- **Icon fixed** — stripped alpha channel from `icon_1024.png` (Apple rejects transparent icons, error 90717)
- **Fastlane scaffolded** — Fastfile, Deliverfile, Appfile with markflow preflight gates and icon alpha check baked in

### Docs
- **Privacy policy** — `docs/privacy-policy.md` documenting zero data collection, zero network requests
- **Support FAQ** — `docs/support.md` covering DNG basics, RAW vs RAW+JPG, focus, 12MP cap
- **README updated** — v0.2 → v1.0, removed "Build-from-source only" limitation, added support page link

### Status: deployed (in App Store review queue)
