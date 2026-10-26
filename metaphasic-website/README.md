# metaPhasic Group Website

Production marketing site for **metaPhasic Group** (`metaphasic.net`) — investments, development, and asset management.

Built with **Vite + React + TypeScript**. Static export is intended for **IONOS** hosting.

## Local development

```bash
cd metaphasic-website
npm install
npm run dev
```

Open the URL Vite prints (typically `http://localhost:5173`).

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

1. Run `npm run build` and upload the **contents** of `dist/` to your IONOS web space document root for `metaphasic.net` (FTP/SFTP, File Manager, or Deploy Now).
2. Ensure `index.html` sits at the domain root (not nested in an extra folder).
3. Keep `favicon.svg` and the `assets/` folder alongside `index.html`.
4. In IONOS DNS, point `metaphasic.net` (and optionally `www`) at your hosting package; enable HTTPS via IONOS SSL.
5. Optional: add an `.htaccess` (Apache) fallback if you later introduce client routes:

```apache
RewriteEngine On
RewriteBase /
RewriteRule ^index\.html$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.html [L]
```

This site is a single-page static app with hash/anchor navigation, so a rewrite is usually unnecessary for the current build.

## Design notes

- Dark, atmospheric UI (gradients + grain), Apple-like hero-first composition and scroll reveals.
- Section structure inspired by institutional firm sites (firm, investments, development, asset management, approach, contact).
- Motion: hero entrance, floating orbs, Intersection Observer reveals — `prefers-reduced-motion` respected.
- Typography: Syne (display) + Manrope (body). Accent: champagne platinum on deep charcoal/steel.

## Legal

**METAPHASIC GROUP CORPORATION**  
1991 Crocker Rd, Westlake, OH 44145-6969, United States  
https://metaphasic.net
