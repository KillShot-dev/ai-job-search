import { useEffect, type CSSProperties } from 'react'
import { Link } from 'react-router-dom'
import { Marquee } from '../components/Marquee'
import { Reveal } from '../components/Reveal'
import { APPS, PLAY_STORE_HOME } from '../data/apps'

export function ProductsPage() {
  useEffect(() => {
    document.title = 'Luma Icon Packs | metaPhasic Group'
    return () => {
      document.title = 'metaPhasic Group | Software Studio'
    }
  }, [])

  // Scroll to hash targets after paint (e.g. marquee → finish card)
  useEffect(() => {
    const hash = window.location.hash.replace('#', '')
    if (!hash) return
    requestAnimationFrame(() => {
      document.getElementById(hash)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
  }, [])

  return (
    <div className="products-page">
      <section className="section products-hero" aria-labelledby="products-title">
        <div className="container">
          <Reveal className="section-head" variant="clip">
            <p className="eyebrow">Products · Luma</p>
            <h1 className="section-title" id="products-title">
              Seven finishes. One home screen.
            </h1>
            <div className="line-accent" aria-hidden="true" />
            <p className="section-lead" style={{ marginTop: '1.5rem' }}>
              Luma is metaPhasic Group’s Android icon pack collection — 315 icons
              per finish, built-in dashboard, wallpapers, and widgets. Each listing
              is <strong>$2.49</strong>. Switch finishes by installing the set you
              want and selecting it in your launcher.
            </p>
            <p className="products-play-row">
              <a
                className="btn btn-primary products-play-btn"
                href={PLAY_STORE_HOME}
                target="_blank"
                rel="noopener noreferrer"
              >
                <span className="play-badge" aria-hidden="true">
                  <svg viewBox="0 0 24 24" width="18" height="18" focusable="false">
                    <path
                      fill="currentColor"
                      d="M3.6 2.3c-.4.2-.6.6-.6 1.1v17.2c0 .5.2.9.6 1.1l.1.1 9.6-9.6v-.4L3.7 2.2l-.1.1zm12.1 7L12.4 12l3.3 2.7 3.9-2.2c.7-.4.7-1.1 0-1.5l-3.9-2.7zM4.3 21.5l8.5-8.5 2.6 2.1-9.9 5.6c-.5.3-1 .2-1.2-.2zm0-19l3.6 3.6L7 8.7 4.3 3.7c.1-.2.2-.2 0-.2z"
                    />
                  </svg>
                </span>
                Google Play
                <span className="btn-arrow" aria-hidden="true">
                  ↗
                </span>
              </a>
            </p>
          </Reveal>
        </div>
      </section>

      <Marquee
        items={APPS.map((a) => ({ label: a.finish, href: `#${a.id}` }))}
        label="Luma finish names — jump to a pack"
      />
      <hr className="divider divider-animated" />

      <section className="section products-grid-section" aria-label="Luma finishes">
        <div className="container">
          <div className="apps-grid">
            {APPS.map((app, i) => (
              <Reveal
                key={app.id}
                id={app.id}
                delay={(i % 3) * 80}
                variant="scale"
                as="article"
                className="app-card"
                style={{ '--app-accent': app.accent } as CSSProperties}
              >
                <a
                  className="app-shot"
                  href={app.storeUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={`${app.name} on Google Play`}
                >
                  <img
                    src={app.screenshot}
                    alt={`${app.finish} finish — icon grid preview`}
                    loading={i < 2 ? 'eager' : 'lazy'}
                    decoding="async"
                  />
                </a>
                <div className="app-body">
                  <div className="app-meta">
                    <span className="app-slot">{app.slot}</span>
                    <span className="app-price">{app.price}</span>
                  </div>
                  <h2 className="app-name">{app.name}</h2>
                  <p className="app-tagline">{app.tagline}</p>
                  <p className="app-desc">{app.description}</p>
                  <ul className="app-highlights">
                    {app.highlights.map((h) => (
                      <li key={h}>{h}</li>
                    ))}
                  </ul>
                  <p className="app-package">
                    <span className="app-package-label">Package</span> {app.packageId}
                  </p>
                  <a
                    className="btn btn-primary app-store-btn"
                    href={app.storeUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {app.storeLabel}
                    <span className="btn-arrow" aria-hidden="true">
                      ↗
                    </span>
                  </a>
                </div>
              </Reveal>
            ))}
          </div>

          <Reveal delay={120}>
            <div className="products-footnote-block">
              <p className="products-footnote">
                Luma requires a custom launcher that supports third-party icon packs.
                Stock Pixel Launcher is unsupported. At launch, launcher mappings cover
                234 of 315 icons (expanding through updates). Luma is not affiliated
                with, endorsed by, or sponsored by any third-party app developer.
              </p>
              <p className="products-footnote">
                <Link to="/#contact">Contact the studio</Link>
                {' · '}
                <a href="https://metaphasic.net">metaphasic.net</a>
              </p>
            </div>
          </Reveal>
        </div>
      </section>
    </div>
  )
}
