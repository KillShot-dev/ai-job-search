# metaPhasic Group Website

Production marketing site for **metaPhasic Group** (`metaphasic.net`) — a software studio designing premium digital products (including the Luma icon pack collection for Android), with asset management and consulting.

Built with **Vite + React + TypeScript** + React Router. Static export is intended for **IONOS** hosting.

## Local development

```bash
cd metaphasic-website
npm install
npm run dev
```

Open the URL Vite prints (typically `http://localhost:5173`).

## Routes

| Path | Page |
|------|------|
| `/` | Home (studio, what we do, approach, contact) |
| `/products` | Products / Apps (7 slots; placeholders until assets arrive) |

## Production build

```bash
cd metaphasic-website
npm run build
```

Output lands in `metaphasic-website/dist/`. Preview locally:

```bash
npm run preview
```

## Deploy to IONOS (metaphasic.net)

1. Run `npm run build` and upload the **contents** of `dist/` to your IONOS web space document root for `metaphasic.net`.
2. Ensure `index.html` sits at the domain root with `assets/`, `favicon.png`, and `.htaccess`.
3. The included `.htaccess` rewrites unknown paths to `index.html` so `/products` works on Apache/IONOS.
4. Point DNS for `metaphasic.net` at the hosting package; enable HTTPS via IONOS SSL.

## Brand assets

| File | Use |
|------|-----|
| `public/assets/metaphasic-logo.jpg` | Source lockup |
| `public/assets/metaphasic-logo.png` | Transparent full logo |
| `public/assets/metaphasic-mark.png` | Icon mark (nav, hero, footer) |
| `public/favicon.png` | Favicon from mark |

## Luma products

Seven Android icon pack finishes live under `/products`. Icon grids ship in
`public/assets/apps/01-luma-*.png` … `07-luma-*.png`. Copy and Play package IDs
are in `src/data/apps.ts`. Store CTAs use
`https://play.google.com/store/apps/details?id=<package>`.

## Legal

**METAPHASIC GROUP CORPORATION**  
1991 Crocker Rd, Westlake, OH 44145-6969, United States  
https://metaphasic.net
