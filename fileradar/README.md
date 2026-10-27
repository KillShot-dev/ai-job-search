# FileRadar

Finder-alternative for macOS (SwiftUI) from **metaPhasic Group**. Shelves by kind, plain-language search, dual-pane/tabs, transfer queue, Drop Stack, on-device OCR/tags, Muse chat (optional), website serials + Mac App Store StoreKit paths.

> **Honest status.** Source in this tree was authored/hardened on Linux. A sibling Mac agent owns `xcodebuild` / signing / notarization. Do **not** claim a verified Mac binary from this cloud checkout.

| Path | Role |
| --- | --- |
| `app/` | Xcode project + SwiftUI sources |
| `demo/` | Browser UI demo (sample library, no network) |
| `site/` | Marketing/sales placeholder site |
| `licensing/` | Stripe test-mode serial backend (stdlib Python) |
| `app/DESIGN.md` | Design principles → code map |
| `finder-replacements-research.md` | Competitive notes (Path Finder, ForkLift, …) |

Support: `support@metaphasic.net`

## Build on a Mac (exact next step)

1. Open `app/FileRadar.xcodeproj` in **Xcode 15+** on **macOS 14+**.
2. Signing & Capabilities → set your **Development Team** (Automatic signing).
3. Confirm **Compile Sources** includes every `.swift` under `FileRadar/` (including `ShipReadyServices.swift`, `StoreKitLicense.swift`, `ShipReadyViews.swift`). Link **Vision, QuickLookUI, PDFKit, AVFoundation, StoreKit, AppKit**.
4. Optional: drop real icons into `FileRadar/Assets.xcassets/AppIcon.appiconset` (catalog exists; slots empty).
5. For Muse: copy `MuseConfig.sample.plist` → `MuseConfig.plist` (gitignored locally) with verified HTTPS dashboard values. Placeholders fail closed.
6. Run (**⌘R**) or:
   ```sh
   cd app
   xcodebuild -project FileRadar.xcodeproj -scheme FileRadar -configuration Debug build
   ```
7. First-run: grant folder access as prompted; Input Monitoring only if you want the global Quick Search hotkey.

Release / notarize / MAS: see `app/README.md` and the ship checklist in the Project store docs.

## Distribution flags (`Info.plist`)

| Key | Purpose |
| --- | --- |
| `FRDistribution` | `direct` (website serials + 14-day Keychain trial) or `mas` (StoreKit) |
| `FRStoreKitProductID` | Public product id (default `com.metaphasicgroup.fileradar.full`) |
| `FRLicensingBaseURL` | Optional HTTPS base for `/validate-serial` + `/activate` (empty = offline checksum) |

**Never** put Stripe secrets, App Store Connect API keys, or webhook secrets in the client.

## Web demo (no Mac required)

```sh
cd demo && python3 -m http.server 8765
# open http://127.0.0.1:8765/
```

## Licensing backend (website)

```sh
cd licensing
export LAUNCH_DATE=2026-10-27 STRIPE_TEST_MODE=1 EMAIL_DRY_RUN=1
python3 server.py
```

See `licensing/README.md`.
