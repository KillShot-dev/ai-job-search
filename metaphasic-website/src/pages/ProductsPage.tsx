import { useEffect, type CSSProperties } from 'react'
import { Link } from 'react-router-dom'
import { Marquee } from '../components/Marquee'
import { Reveal } from '../components/Reveal'
import { APPS } from '../data/apps'

export function ProductsPage() {
  useEffect(() => {
    document.title = 'Luma Icon Packs | metaPhasic Group'
    return () => {
      document.title = 'metaPhasic Group | Software Studio'
    }
  }, [])

  return (
    <div className="products-page">
      <section className="section products-hero" aria-labelledby="products-title">
        <div className="container">
          <Reveal className="section-head" variant="clip">
            <p className="eyebrow">Products · Luma</p>
            <h1 className="section-title" id="products-title">
              Seven finishes. One considered home screen.
            </h1>
            <div className="line-accent" aria-hidden="true" />
            <p className="section-lead" style={{ marginTop: '1.5rem' }}>
              Luma is metaPhasic Group’s Android icon pack collection — 315 icons
              per finish, built-in dashboard, wallpapers, and widgets. Each listing
              is <strong>$2.49</strong>. Switch finishes by installing the set you
              want and selecting it in your launcher.
            </p>
          </Reveal>
        </div>
      </section>

      <Marquee
        items={APPS.map((a) => a.finish)}
        label="Luma finish names"
      />
      <hr className="divider divider-animated" />

      <section className="section products-grid-section" aria-label="Luma finishes">
        <div className="container">
          <div className="apps-grid">
            {APPS.map((app, i) => (
              <Reveal key={app.id} delay={(i % 3) * 80} variant="scale" as="article">
                <article
                  className="app-card"
                  id={app.id}
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
                </article>
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
