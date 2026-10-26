import { Reveal } from './Reveal'

export function About() {
  return (
    <section className="section" id="about" aria-labelledby="about-title">
      <div className="container">
        <div className="about-grid">
          <div>
            <Reveal className="section-head">
              <p className="eyebrow">The firm</p>
              <h2 className="section-title" id="about-title">
                Clarity of purpose. Continuity of stewardship.
              </h2>
              <div className="line-accent" aria-hidden="true" />
            </Reveal>
            <Reveal delay={120}>
              <p className="section-lead">
                metaPhasic Group is an investment and asset management firm based
                in Westlake, Ohio. We partner with operators and owners to deploy
                capital thoughtfully — across investments, development, and the
                ongoing care of assets that matter.
              </p>
            </Reveal>
            <Reveal delay={220}>
              <div className="stat-row" role="list">
                <div className="stat" role="listitem">
                  <div className="stat-value">3</div>
                  <div className="stat-label">Core disciplines</div>
                </div>
                <div className="stat" role="listitem">
                  <div className="stat-value">OH</div>
                  <div className="stat-label">United States</div>
                </div>
                <div className="stat" role="listitem">
                  <div className="stat-value">LT</div>
                  <div className="stat-label">Long-term focus</div>
                </div>
              </div>
            </Reveal>
          </div>

          <Reveal delay={180} variant="scale">
            <aside className="about-aside">
              <p>
                We believe durable returns come from <strong>rigorous underwriting</strong>,
                aligned incentives, and patient ownership — not from chasing
                cycles or fashion.
              </p>
              <p>
                Every engagement is grounded in fundamentals: where value is
                created, how risk is priced, and how assets are improved over
                time.
              </p>
            </aside>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
