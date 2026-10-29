import { Reveal } from './Reveal'

export function Contact() {
  return (
    <section className="section" id="contact" aria-labelledby="contact-title">
      <div className="container">
        <Reveal className="section-head">
          <p className="eyebrow">Contact</p>
          <h2 className="section-title" id="contact-title">
            Let’s build something lasting.
          </h2>
          <div className="line-accent" aria-hidden="true" />
        </Reveal>

        <Reveal delay={120} variant="scale">
          <div className="contact-panel contact-panel-simple">
            <div className="contact-details">
              <p className="contact-lead">
                For product partnerships, consulting, and Luma inquiries — reach
                out through <a href="https://metaphasic.net">metaphasic.net</a>.
              </p>
              <div className="contact-block">
                <h3>Studio</h3>
                <p>metaPhasic Group</p>
              </div>
              <div className="contact-block">
                <h3>Legal entity</h3>
                <p>METAPHASIC GROUP CORPORATION</p>
              </div>
            </div>
            <div className="contact-map-hint">
              We keep engagements focused on the work: thoughtful design, solid
              engineering, and products people enjoy using. Prefer starting via
              the public site — no forms required here.
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
