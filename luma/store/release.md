# Release instructions

Nothing in this list has been done for Luma. The Android project under `luma/android` is source. This machine has no Android SDK, so it was not assembled.

## Before a Play upload

1. Finish original icons for every package in a fresh Top Free snapshot of at least 300 apps. Do not count recolors, duplicates, or the system set.
2. Rebuild with `python3 luma/tools/build_icons.py` and `python3 luma/tools/validate.py`.
3. On a device, apply the pack in at least one community launcher and, if One UI is a target, in Samsung Theme Park. Record pass or fail per package in `tracker/progress.csv`. Fix activity names that do not match.
4. Open the project in Android Studio, let it generate a Gradle wrapper, and build a release Android App Bundle.
5. Sign the bundle with the upload key stored in Play Console. Do not commit the keystore.
6. Create the Play app. Complete content rating, data safety, and a privacy policy if the console requires one. This prototype declares no permissions and the dashboard loads a local asset.
7. Upload the feature graphic, a 512 icon, and phone screenshots taken from the tested launcher. Replace the prototype feature graphic, which is labeled as unfinished.
8. Use the finished-pack description only after the icon count in the text matches the build.
9. Run a closed test, then a paid production release.

## Data handling

The dashboard WebView loads `file:///android_asset/dashboard/index.html` with JavaScript disabled. No INTERNET permission is declared. If that stays true, the data-safety form should say the app does not collect user data. Re-check the form if analytics or a network call is added later.
