import { Reveal } from './Reveal'

const STEPS = [
  {
    num: '01',
    title: 'Discover',
    body: 'We start with people and constraints — who it’s for, what success looks like, and where craft will matter most.',
  },
  {
    num: '02',
    title: 'Design',
    body: 'From first sketch to interaction detail, we shape interfaces that feel inevitable: clear, calm, and considered.',
  },
  {
    num: '03',
    title: 'Build',
    body: 'Solid engineering without shortcuts. Performance, accessibility, and maintainability are part of the definition of done.',
  },
  {
    num: '04',
    title: 'Refine & steward',
    body: 'We stay close after ship — polishing, iterating, and helping partners grow software that lasts.',
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
                Discipline from sketch to pixel.
              </h2>
              <div className="line-accent" aria-hidden="true" />
            </Reveal>
            <Reveal delay={100}>
              <p className="section-lead">
                The same standard we hold for Luma and our own products applies
                to every engagement: thoughtful design, solid engineering, and
                outcomes people enjoy using.
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
