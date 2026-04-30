# Changelog

All notable shipped features and changes, organized by date.
Updated every session via `/save-session`.

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
