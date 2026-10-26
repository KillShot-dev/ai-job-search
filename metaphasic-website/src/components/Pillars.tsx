import { Link } from 'react-router-dom'
import { Reveal } from './Reveal'

const PILLARS = [
  {
    id: 'products',
    index: '01',
    title: 'Premium products',
    body: 'We ship digital products with obsessive craft — including the Luma icon pack collection for Android (seven finishes) — where every interaction earns its place.',
    points: [
      'Luma: Regular, Dark, Gradient, Glyph, Clear, Prism, Midnight',
      'Native-quality mobile experiences',
      'Design systems that scale with the product',
    ],
  },
  {
    id: 'work',
    index: '02',
    title: 'Design & engineering',
    body: 'Thoughtful design meets solid engineering. We build software people enjoy using — without shortcuts that show up later as debt.',
    points: [
      'End-to-end product development',
      'Performance, accessibility, polish',
      'Clear collaboration with partners',
    ],
  },
  {
    id: 'consulting',
    index: '03',
    title: 'Asset management & consulting',
    body: 'We help partners plan, build, and grow software that lasts — strategy, systems, and stewardship for digital assets that matter.',
    points: [
      'Product strategy and roadmaps',
      'Portfolio and asset stewardship',
      'Ongoing advisory for growing teams',
    ],
  },
] as const

export function Pillars() {
  return (
    <section className="section" id="work" aria-label="What we do">
      <div className="container">
        <Reveal className="section-head">
          <p className="eyebrow">What we do</p>
          <h2 className="section-title">Products. Craft. Partnership.</h2>
          <div className="line-accent" aria-hidden="true" />
          <p className="section-lead" style={{ marginTop: '1.5rem' }}>
            From our own apps to partner engagements — one standard of care
            across design, engineering, and consulting.
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

        <Reveal delay={200}>
          <p className="products-cta-row">
            <Link className="btn btn-ghost" to="/products">
              Explore the product lineup →
            </Link>
          </p>
        </Reveal>
      </div>
    </section>
  )
}
