# Release instructions

A signed release build was produced on Oct 25, 2026, 7:53 PM PT.

| File | What it is |
| --- | --- |
| `luma-1.0.0-release.aab` | The file to upload. New Play apps must be an Android App Bundle. |
| `luma-1.0.0-release.apk` | The same version, signed, for a device install. Play Console will not take this APK for a new app. |
| `luma-upload.jks` | Upload key. Not in git. Required for every future update. |

Package `com.metaphasic.luma`, versionCode 1, versionName 1.0.0, minSdk 23, targetSdk 36, compileSdk 36. No permissions are declared. `apksigner` verified the APK (JAR and APK Signature Scheme v2). `jarsigner` verified the bundle. The certificate subject is `CN=metaPhasic Group, O=metaPhasic Group, C=US`. SHA-256 fingerprint `66:32:A2:7C:E4:31:04:24:AA:3F:14:35:CF:FE:54:F3:AD:03:03:68:B4:C9:40:01:7D:26:52:D7:8C:14:8A:62`.

The upload keystore and `keystore.properties` are not committed. Rebuild with the Android SDK installed and `keystore.properties` present:

```bash
cd luma/android
./gradlew bundleRelease assembleRelease
```

## Still required before Play will publish

1. On a device, apply the pack in at least one community launcher and, if One UI is a target, in Samsung Theme Park. Record pass or fail per package. Fix activity names that do not match. That test has not been run.
2. Create the Play app and upload the `.aab`. The first upload enrolls this upload key in Play App Signing.
3. Complete content rating, data safety, and a privacy policy if the console requires one. This build declares no permissions and the dashboard loads a local asset.
4. Upload the feature graphic, a 512 icon, and phone screenshots taken from a tested launcher.
5. Use store text that matches this build. Ranks 200–300 are category-chart apps, not official overall ranks. The in-app page still says the logo set is a prototype and that launcher tests are 0.
6. Run a closed test, then a paid production release.

## Data handling

The dashboard WebView loads the packaged HTML through `WebViewAssetLoader` with JavaScript disabled. No INTERNET permission is declared, and that virtual host is served from the app's own assets. If that stays true, the data-safety form should say the app does not collect user data. Re-check the form if analytics or a network call is added later.
