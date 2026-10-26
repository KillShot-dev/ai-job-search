import { Reveal } from './Reveal'

const STEPS = [
  {
    num: '01',
    title: 'Understand',
    body: 'We begin with context — objectives, constraints, and the economics of the opportunity — before capital or structure is proposed.',
  },
  {
    num: '02',
    title: 'Underwrite',
    body: 'Assumptions are tested. Risks are priced. Scenarios are examined so decisions rest on clarity, not optimism alone.',
  },
  {
    num: '03',
    title: 'Structure',
    body: 'Capital, governance, and incentives are aligned so every party shares a durable interest in outcomes.',
  },
  {
    num: '04',
    title: 'Steward',
    body: 'After closing, we stay engaged — monitoring performance, adapting plans, and protecting long-term value.',
  },
] as const

export function Approach() {
  return (
    <section className="section" id="approach" aria-labelledby="approach-title">
      <div className="container">
        <div className="approach-layout">
          <div>
            <Reveal className="section-head">
              <p className="eyebrow">Approach</p>
              <h2 className="section-title" id="approach-title">
                A process built for judgment.
              </h2>
              <div className="line-accent" aria-hidden="true" />
            </Reveal>
            <Reveal delay={100}>
              <p className="section-lead">
                Inspired by the best institutional practice — deliberate,
                transparent, and oriented toward multi-year outcomes rather than
                short-term noise.
              </p>
            </Reveal>
          </div>

          <ol className="approach-steps">
            {STEPS.map((s, i) => (
              <Reveal key={s.num} delay={80 + i * 100} as="li" className="approach-step">
                <span className="step-num" aria-hidden="true">
                  {s.num}
                </span>
                <div>
                  <h3>{s.title}</h3>
                  <p>{s.body}</p>
                </div>
              </Reveal>
            ))}
          </ol>
        </div>
      </div>
    </section>
  )
}
