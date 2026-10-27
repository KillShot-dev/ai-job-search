import { Link } from 'react-router-dom'
import { BrandMark } from './BrandMark'
import { Magnetic } from './Magnetic'

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
        <div className="hero-lockup">
          <BrandMark className="hero-mark" size={120} alt="" />
          <h1 className="hero-brand" id="hero-brand">
            <span className="hero-brand-line">metaPhasic</span>
            <span className="hero-brand-sub">Group</span>
          </h1>
        </div>
        <p className="hero-tagline">
          A software studio built on one standard: world-class work, no
          shortcuts. Premium digital products — including Luma for Android —
          plus asset management and consulting.
        </p>
        <div className="hero-actions">
          <Magnetic strength={0.22}>
            <Link className="btn btn-primary" to="/products">
              View products
            </Link>
          </Magnetic>
          <Magnetic strength={0.22}>
            <a className="btn btn-ghost" href="#about">
              About the studio
            </a>
          </Magnetic>
        </div>
      </div>

      <div className="hero-scroll" aria-hidden="true">
        <span>Scroll</span>
        <div className="hero-scroll-line" />
      </div>
    </section>
  )
}
