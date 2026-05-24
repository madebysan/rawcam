# Changelog

All notable shipped features and changes, organized by date.
Updated every session via `/save-session`.

---

## 2026-05-23

### Features
- **Manual controls drawer:** exposed the existing manual exposure and white-balance controls above the shutter, with ISO, shutter speed, presets, Kelvin adjustment, and a tappable AF/AE unlock badge.
- **Capture aids:** added grid, horizon level, clipping warnings, self-timer, EV compensation, and separate focus/exposure targeting.
- **Shooting workflow:** added anti-shake shutter, three-shot RAW bracketing, and a last-shot details panel.
- **Competitor parity batch:** added lens selection, volume-button shutter, persistent settings, a last-shot session strip, and an App Shortcut for Shortcuts/Siri/Action Button launch.
- **Focus peaking rollback:** removed the first focus-peaking implementation after real-device testing showed it could destabilize the camera UI.
- **Focus lock stabilization:** removed the duplicate live preview loupe and changed long-press to focus-only lock so it cannot black out the preview by hard-locking exposure.
- **Zebra clipping warning:** added lightweight yellow zebra stripes when highlights clip, giving `TAP METER` users a stronger exposure warning without live image overlays.
- **Info sheet refresh:** updated the in-app help sheet so it matches the current controls: focus-only lock, metering, zebra warnings, lens switching, capture aids, volume shutter, and App Shortcut launch.
- **Control design polish:** applied a Not Boring-inspired pass to the camera controls with amber identity color, icon/readout chips, dimensional active states, a richer drawer surface, and a more instrument-like shutter.
- **Collapsible tools drawer:** replaced the always-visible 12-control grid with a compact TOOLS handle. Tap or swipe up to reveal controls, swipe down to hide them and restore preview space.

### Docs
- **Feature copy:** updated README, support docs, backlog, and App Store metadata for the new capture controls.

### Status: local build passing

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
