# Only Sarang can do these (agents must not)

Paid Apple Developer Program enrollment for **metaPhasic Group Corporation**, legal entity paperwork, banking, and App Store Connect submission are owner-only. Agents prepare code and docs; they do **not** upload, notarize with your credentials, or store secrets.

## Legal / Apple account
- [ ] Enroll or renew **Apple Developer Program** as **metaPhasic Group Corporation** (Organization)
- [ ] Complete **D-U-N-S** verification for the corporation (Apple’s flow)
- [ ] Accept **Paid Applications** / **Apple Developer** agreements in App Store Connect
- [ ] Complete **bank / tax** forms in App Store Connect (never paste EIN into chat, git, or Project docs)

## Certificates & signing (on Mac Studio)
- [ ] Xcode → Settings → Accounts → add the org Apple ID / team
- [ ] Create / renew **Apple Distribution** certificate (Mac App Store)
- [ ] Create / renew **Mac Installer Distribution** if shipping a pkg via MAS tooling that requires it
- [ ] Create / renew **Developer ID Application** (+ Installer if needed) for **direct sale only**
- [ ] Confirm `security find-identity -v -p codesigning` shows those identities
- [ ] Set **DEVELOPMENT_TEAM** on the FileRadar target

## App Store Connect product
- [ ] Create Mac app record for `com.metaphasicgroup.fileradar`
- [ ] Create non-consumable IAP / unlock product id **`com.metaphasicgroup.fileradar.full`** (must match Info.plist)
- [ ] Pricing, availability, review contact = support@metaphasic.net
- [ ] Privacy policy URL hosting this repo’s `docs/store/privacy-policy.md` (or site mirror)
- [ ] Age rating questionnaire
- [ ] Screenshots per `screenshot-plan.md`
- [ ] Paste `review-notes.md` into Review Notes
- [ ] Answer export compliance per `export-compliance.md`

## Archive & submit (MAS) — Sarang executes
```sh
# Example only — Sarang runs after Team + certs exist.
cd ~/Desktop/FileRadar/FileRadar/app
xcodebuild -scheme FileRadarMAS -configuration Release \
  -destination 'generic/platform=macOS' \
  FR_DISTRIBUTION=mas \
  -archivePath ~/Desktop/FileRadar/build/FileRadar-MAS.xcarchive \
  archive
# Then Organizer → Distribute App → App Store Connect
# OR: xcodebuild -exportArchive … (with App Store export options plist)
```
Agents must **not** run upload/submit with your credentials.

## Direct sale (prepare only — see direct-sale-prep.md)
- [ ] Developer ID sign + notarize + staple
- [ ] Host DMG/ZIP on metaphasic site
- [ ] Website serial issuance stays outside the MAS binary
