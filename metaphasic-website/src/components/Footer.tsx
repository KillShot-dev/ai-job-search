import { Link } from 'react-router-dom'
import { BrandMark } from './BrandMark'

export function Footer() {
  const year = new Date().getFullYear()

  return (
    <footer className="footer">
      <div className="container footer-inner">
        <div className="footer-brand-block">
          <Link to="/" className="footer-brand" aria-label="metaPhasic Group home">
            <BrandMark size={32} />
            <span>metaPhasic Group</span>
          </Link>
          <div className="footer-legal">
            <strong>METAPHASIC GROUP CORPORATION</strong>
          </div>
        </div>
        <div className="footer-meta">
          <Link to="/products">Products</Link>
          <span className="footer-sep" aria-hidden="true">
            ·
          </span>
          <a href="https://metaphasic.net">metaphasic.net</a>
          <br />© {year} metaPhasic Group. All rights reserved.
        </div>
      </div>
    </footer>
  )
}
