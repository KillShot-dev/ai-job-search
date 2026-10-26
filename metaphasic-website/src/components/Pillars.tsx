import { Reveal } from './Reveal'

const PILLARS = [
  {
    id: 'investments',
    index: '01',
    title: 'Investments',
    body: 'We seek opportunities where capital, judgment, and operational insight compound. Our investment approach balances conviction with disciplined risk management.',
    points: [
      'Selective equity and structured capital',
      'Partnership with aligned management teams',
      'Underwriting grounded in fundamentals',
    ],
  },
  {
    id: 'development',
    index: '02',
    title: 'Development',
    body: 'From concept through delivery, we advance projects that create lasting economic and community value — with attention to timing, quality, and capital efficiency.',
    points: [
      'Project structuring and capital planning',
      'Execution oversight and milestone discipline',
      'Value creation through thoughtful design',
    ],
  },
  {
    id: 'asset-management',
    index: '03',
    title: 'Asset Management',
    body: 'We steward assets with a long horizon — optimizing performance, protecting downside, and positioning portfolios for resilient growth.',
    points: [
      'Active oversight and reporting',
      'Lifecycle planning and reinvestment',
      'Alignment with ownership objectives',
    ],
  },
] as const

export function Pillars() {
  return (
    <section className="section" aria-label="What we do">
      <div className="container">
        <Reveal className="section-head">
          <p className="eyebrow">Capabilities</p>
          <h2 className="section-title">Three disciplines. One standard of care.</h2>
          <div className="line-accent" aria-hidden="true" />
          <p className="section-lead" style={{ marginTop: '1.5rem' }}>
            Investments, development, and asset management — practiced as
            connected crafts, not siloed products.
          </p>
        </Reveal>

        <div className="pillars">
          {PILLARS.map((p, i) => (
            <Reveal
              key={p.id}
              id={p.id}
              delay={i * 120}
              variant="scale"
              as="article"
              className="pillar"
            >
              <div className="pillar-index">{p.index}</div>
              <h3>{p.title}</h3>
              <p>{p.body}</p>
              <ul className="pillar-list">
                {p.points.map((point) => (
                  <li key={point}>{point}</li>
                ))}
              </ul>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}
