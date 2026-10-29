# Compatibility

Icon packs do not restyle the stock Pixel launcher or the default Google TV / phone launcher UI. A buyer needs either a launcher that reads an icon pack, or Samsung’s Theme Park path on One UI.

## Intended, untested

These are the usual routes for a pack that ships `appfilter.xml`, `drawable.xml`, and `appmap.xml`. None were installed or opened for Luma.

- Nova Launcher, which looks for `res/xml/appfilter.xml` and `ComponentInfo` entries
- Lawnchair and other launchers that follow that same resource layout
- Launchers that read ADW-style `appmap.xml`
- Samsung Theme Park on One UI 4 and newer, which Outline’s listing also documents as the One UI route

The manifest declares `com.novalauncher.THEME` and `org.adw.launcher.icons.ACTION_PICK_ICON` so a picker can see the activity. Those filters are candidates. They were not confirmed.

## Mapping status

`tracker/progress.csv` column `mapping_verified` is false for every row.

`appfilter.xml` includes component names that have been widely published for a few well-known apps (WhatsApp, Instagram, Facebook, Messenger, Telegram, TikTok, X, Snapchat) and for common AOSP / Pixel system activities. OEM skins rename those activities. An unverified name will simply fail to match.

Apps in the drawn set without a published activity name have a drawable and no `appfilter` line. Guessed activity names were left out.

## Disclosure for the listing

State, in the Play description, that a third-party launcher or Samsung Theme Park is required. Do not promise support for the stock Pixel launcher.
