# FileRadar — store submission pack

Prepare-only materials for Mac App Store and direct sale. No credentials, no upload.

| Doc | Purpose |
| --- | --- |
| [listing-copy.md](listing-copy.md) | Name, subtitle, description, keywords, category |
| [privacy-policy.md](privacy-policy.md) | Privacy policy text (host publicly before submit) |
| [review-notes.md](review-notes.md) | App Review notes |
| [screenshot-plan.md](screenshot-plan.md) | Mac screenshot sizes + shot list |
| [export-compliance.md](export-compliance.md) | Encryption / export answers |
| [sarang-only-checklist.md](sarang-only-checklist.md) | Owner-only Apple org / certs / ASC / bank-tax (no EIN in repo) |
| [direct-sale-prep.md](direct-sale-prep.md) | Developer ID + notarize steps (prepare only) |

Support contact used everywhere: **support@metaphasic.net**

MAS build stamp: pass `FR_DISTRIBUTION=mas` to `xcodebuild` (scheme **FileRadarMAS**) so Info.plist `FRDistribution` becomes `mas` and serial unlock stays off.
