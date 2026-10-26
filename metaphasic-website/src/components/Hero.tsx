export function Hero() {
  return (
    <section className="hero" id="top" aria-labelledby="hero-brand">
      <div className="hero-visual" aria-hidden="true">
        <div className="hero-orb hero-orb-a" />
        <div className="hero-orb hero-orb-b" />
        <div className="hero-orb hero-orb-c" />
        <div className="hero-grid" />
        <div className="hero-fade" />
      </div>

      <div className="hero-content">
        <h1 className="hero-brand" id="hero-brand">
          metaPhasic
          <span className="hero-brand-sub">Group</span>
        </h1>
        <p className="hero-tagline">
          Investments, development, and asset management — disciplined capital
          for lasting value.
        </p>
        <div className="hero-actions">
          <a className="btn btn-primary" href="#about">
            Explore the firm
          </a>
          <a className="btn btn-ghost" href="#contact">
            Contact
          </a>
        </div>
      </div>

      <div className="hero-scroll" aria-hidden="true">
        <span>Scroll</span>
        <div className="hero-scroll-line" />
      </div>
    </section>
  )
}
