# Export compliance answers (App Store Connect)

FileRadar ships `ITSAppUsesNonExemptEncryption = false` in Info.plist.

## Recommended ASC answers
1. **Does your app use encryption?**  
   Yes — only HTTPS via system frameworks (URLSession / Network) and Apple platform crypto (Keychain, CryptoKit SHA-256 for machine hash / file hashing). No proprietary encryption algorithms.

2. **Is your app exempt under category…?**  
   Yes — encryption is limited to authentication / HTTPS / disk access controls provided by the OS. Select the standard exemption for HTTPS-only apps (wording varies by ASC year; match the “uses encryption only for HTTPS / authentication” option).

3. **Does your app qualify for any exemptions?**  
   Yes — exempt.

4. **Annual self-classification report**  
   Usually not required for HTTPS-only exempt apps; confirm current ASC text when submitting.

## Not used
- Custom VPN, custom TLS stacks, proprietary ciphers
- End-to-end messaging crypto beyond system TLS

No EAR commodity classification paperwork is prepared in-repo; Sarang confirms final ASC checkboxes at submit time.
