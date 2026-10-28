# FileRadar Privacy Policy

**Effective date:** 2026-10-27  
**Contact:** support@metaphasic.net  
**Publisher:** metaPhasic Group Corporation

This policy covers the FileRadar macOS app distributed on the Mac App Store and, where applicable, direct downloads from metaPhasic.

## Summary
FileRadar indexes and analyzes files on your Mac. Core features do not upload your files. Optional Muse chat is separate and only runs when you connect it.

## Data FileRadar processes on your Mac
- File names, paths, sizes, dates, and type metadata for folders you grant access to
- Optional on-device text recognition (OCR) results for images and PDFs you view or index
- Tags, favorites, saved searches, theme, and similar preferences stored in UserDefaults / app container
- Security-scoped bookmarks for folders you add (so access survives relaunch)
- License / trial state in the Keychain (and Mac App Store purchase status via StoreKit)

## Data that may leave your Mac
- **Mac App Store purchase / restore:** handled by Apple StoreKit. We do not receive your payment card details.
- **Optional Muse chat:** if you connect Muse, messages and metadata you choose to send go to the HTTPS Model API endpoint configured for that feature. File contents and OCR text are not sent unless a future tool you explicitly approve does so. You can disconnect and delete local chat history in Settings.
- **Optional direct-sale license server (website builds only):** if a licensing base URL is configured, activation may send a hashed machine identifier and serial. Mac App Store builds do not use website serial unlock.

## Tracking
FileRadar does not use App Tracking Transparency tracking. The privacy manifest declares `NSPrivacyTracking = false` and no tracking domains.

## Permissions
- **Downloads / Documents / Desktop:** only after system prompts or folder pickers; see usage strings in the app
- **Microphone / Speech recognition:** only for optional Muse voice commands; audio is not stored by FileRadar
- **Full Disk Access:** not required and not entitled. You may grant it in System Settings if you want broader indexing; FileRadar cannot grant it to itself

## Children
FileRadar is not directed at children under 13.

## Retention
On-device index data lives in the app sandbox until you remove the app or clear data. Chat history stays until you delete it. Apple retains App Store transaction records under Apple’s policies.

## Your choices
- Remove folders from indexing / revoke bookmarks
- Deny microphone or speech permission
- Log out of Muse / clear API key / delete chat history
- Uninstall FileRadar to remove its container data

## Changes
We may update this policy. Material changes will be reflected in the App Store privacy nutrition labels and this document.

## Contact
support@metaphasic.net
