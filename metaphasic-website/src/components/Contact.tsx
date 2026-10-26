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
          <div className="contact-panel">
            <div className="contact-details">
              <div className="contact-block">
                <h3>Office</h3>
                <p>
                  1991 Crocker Rd
                  <br />
                  Westlake, OH 44145-6969
                  <br />
                  United States
                </p>
              </div>
              <div className="contact-block">
                <h3>Online</h3>
                <p>
                  <a href="https://metaphasic.net">metaphasic.net</a>
                </p>
              </div>
              <div className="contact-block">
                <h3>Legal entity</h3>
                <p>METAPHASIC GROUP CORPORATION</p>
              </div>
            </div>
            <div className="contact-map-hint">
              Based in Westlake, Ohio — for product partnerships, consulting, and
              asset management inquiries. Reach out via metaphasic.net.
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}
