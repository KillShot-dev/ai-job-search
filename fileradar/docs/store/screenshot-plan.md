# Screenshot plan (Mac App Store)

Accepted Mac screenshot sizes (pick one primary set; provide 1–10 images):

| Display | Size (px) |
| --- | --- |
| Mac 16" / 14" (Liquid Retina XDR) | **3456 × 2234** or **3024 × 1964** |
| MacBook Air 13" | **2560 × 1600** |
| Mac 21.5" iMac | **4096 × 2304** (if still offered) |

Apple’s current ASC Mac screenshot guidance: use the sizes listed in App Store Connect for the selected Mac display. Prefer **16:10** window captures that fill the frame; do not letterbox.

## Capture setup
1. Build the **MAS** binary (`FRDistribution=mas`) or use a direct build with trial active so UI is unlocked.
2. Use Look **Modern** or **Elegant**, Appearance **Light** (or System on a light desktop).
3. Hide unrelated desktop clutter; set Downloads to a tidy demo set (mix of images, PDFs, archives).
4. Window ≈ 1280×800 logical then export at the target pixel size (or capture full Retina and crop).

## Shot list (5–7)
1. **Home shelves** — brand-visible window titled FileRadar, Images/Documents shelves filled.
2. **Search** — query with visible filter chips and results.
3. **Inspector / OCR** — image selected, recognised text visible.
4. **Duplicates** — group with keeper highlighted (trial/full unlocked).
5. **Clean Up** — cards list, no scary red delete chrome.
6. **Disk Map or Timeline** — one atmospheric secondary view.
7. **Unlock sheet** — StoreKit Buy / Restore only (no serial field).

## Do not show
- Serial-entry fields (MAS binary must not)
- Secrets, API keys, real email inboxes, personal photos you lack rights to
- Fake “#1 on App Store” badges or review-star overlays

## Export
PNG, sRGB, no transparency. Name `mas-01-home.png` … `mas-07-unlock.png`.
