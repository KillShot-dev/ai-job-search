# App Review notes (paste into App Store Connect)

## Demo account
No account required for core FileRadar features.

Optional Muse chat needs a developer-configured Model API. Reviewers can ignore Muse; the Muse sidebar shows a connect state without credentials. Do not require Muse for acceptance of shelves, search, OCR, duplicates, or Clean Up.

## How to exercise paid features
1. Launch FileRadar.
2. Trial should be active for 14 days from first launch (Keychain stamp) — paid features unlock during trial.
3. After trial, use in-app **Unlock** → StoreKit product `com.metaphasicgroup.fileradar.full` (Buy / Restore).
4. This Mac App Store binary does **not** accept website serial numbers.

## Sandbox / disk access
- Default index: Downloads (sandbox downloads entitlement).
- Additional folders: File → Add Folder (user-selected read/write + security-scoped bookmarks).
- FileRadar does **not** claim Full Disk Access via entitlement. Whole-disk indexing only works if the user separately grants Full Disk Access in System Settings.

## Permissions you may see
- Downloads / Documents / Desktop usage strings when those folders are used
- Microphone + Speech Recognition only if testing Muse voice

## Contact
support@metaphasic.net
