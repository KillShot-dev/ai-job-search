import { Reveal } from './Reveal'

export function About() {
  return (
    <section className="section" id="about" aria-labelledby="about-title">
      <div className="container">
        <div className="about-grid">
          <div>
            <Reveal className="section-head" variant="clip">
              <p className="eyebrow">The studio</p>
              <h2 className="section-title" id="about-title">
                World-class work. No shortcuts.
              </h2>
              <div className="line-accent" aria-hidden="true" />
            </Reveal>
            <Reveal delay={120}>
              <p className="section-lead">
                metaPhasic Group is a software studio built on one standard:
                world-class work, no shortcuts. We design and develop premium
                digital products — including the Luma icon pack collection for
                Android — where every detail is considered, from the first
                sketch to the final pixel.
              </p>
            </Reveal>
            <Reveal delay={220}>
              <div className="stat-row" role="list">
                <div className="stat" role="listitem">
                  <div className="stat-value">7</div>
                  <div className="stat-label">Luma finishes</div>
                </div>
                <div className="stat" role="listitem">
                  <div className="stat-value">315</div>
                  <div className="stat-label">Icons per Luma finish</div>
                </div>
                <div className="stat" role="listitem">
                  <div className="stat-value">∞</div>
                  <div className="stat-label">Care for every pixel</div>
                </div>
              </div>
            </Reveal>
          </div>

          <Reveal delay={180} variant="scale">
            <aside className="about-aside">
              <p>
                Beyond our own products, we offer{' '}
                <strong>asset management and consulting</strong>, helping
                partners plan, build, and grow software that lasts.
              </p>
              <p>
                Whether it&apos;s an app, a design system, or a product
                strategy, we bring the same discipline to every engagement:
                thoughtful design, solid engineering, and products people
                genuinely enjoy using.
              </p>
            </aside>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
