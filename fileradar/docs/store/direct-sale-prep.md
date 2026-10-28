# Direct sale path — prepare only (do not execute from agents)

Website / Developer ID distribution is separate from the Mac App Store binary. Keep `FRDistribution=direct` for this path so serial unlock remains available. Do **not** ship StoreKit purchase UI as the only unlock on a Developer ID build that also sells serials without a clear UX fork — MAS builds must be `FRDistribution=mas` with no serial field.

## Prerequisites (Sarang)
1. **Developer ID Application** certificate installed on the Mac Studio.
2. Optional **Developer ID Installer** if shipping a `.pkg`.
3. `notarytool` Keychain profile (e.g. `AC_NOTARY`) via `xcrun notarytool store-credentials` — never commit the password.
4. Team ID + Apple ID with Developer Program access.

## Build (unsigned draft is already proven on this Mac; signing is Sarang’s step)
```sh
cd ~/Desktop/FileRadar/FileRadar/app
xcodebuild -scheme FileRadar -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath ~/Desktop/FileRadar/build/DerivedDataDirect \
  build
```

## Sign (Sarang — replace IDENTITY)
```sh
APP=~/Desktop/FileRadar/dist/FileRadar-Direct.app
IDENTITY="Developer ID Application: metaPhasic Group Corporation (TEAMID)"
codesign --force --deep --options runtime --timestamp \
  --entitlements FileRadar/FileRadar.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

## Notarize + staple
```sh
ditto -c -k --keepParent "$APP" ~/Desktop/FileRadar/dist/FileRadar.zip
xcrun notarytool submit ~/Desktop/FileRadar/dist/FileRadar.zip \
  --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "$APP"
spctl -a -vv -t install "$APP"
```

## Package for the site
- Prefer a compressed `.zip` of the stapled `.app`, or a notarized DMG.
- Gatekeeper must accept (`spctl` clean).
- Host download + serial purchase on the metaphasic site; support@metaphasic.net for license moves.

## Honest limits
- Sandbox still applies if you keep App Sandbox on (recommended): no silent whole-disk access.
- Full Disk Access remains a user System Settings grant.
- Do not embed Stripe secret keys or App Store Connect API keys in the app.

## Not done by agents
No notarization credentials, no upload to the website CDN, no live charge configuration in this task.
