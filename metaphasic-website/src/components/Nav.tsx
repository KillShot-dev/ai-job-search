import { useEffect, useState } from 'react'
import { Link, NavLink, useLocation } from 'react-router-dom'
import { useNavScroll } from '../hooks/useNavScroll'
import { BrandMark } from './BrandMark'

const HOME_LINKS = [
  { href: '/#about', label: 'Studio' },
  { href: '/#work', label: 'What we do' },
  { href: '/products', label: 'Products', route: true },
  { href: '/#approach', label: 'Approach' },
  { href: '/#contact', label: 'Contact' },
] as const

export function Nav() {
  const scrolled = useNavScroll()
  const [open, setOpen] = useState(false)
  const location = useLocation()

  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

  useEffect(() => {
    setOpen(false)
  }, [location.pathname])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const close = () => setOpen(false)

  return (
    <>
      <header className={`nav${scrolled || open ? ' is-scrolled' : ''}`}>
        <div className="nav-inner">
          <Link
            className="brand"
            to="/"
            onClick={close}
            aria-label="metaPhasic Group home"
          >
            <BrandMark size={28} />
            <span className="brand-text">
              metaPhasic <span>Group</span>
            </span>
          </Link>

          <nav className="nav-links" aria-label="Primary">
            {HOME_LINKS.map((l) =>
              'route' in l && l.route ? (
                <NavLink
                  key={l.href}
                  to="/products"
                  className={({ isActive }) => (isActive ? 'is-active' : undefined)}
                >
                  {l.label}
                </NavLink>
              ) : (
                <a key={l.href} href={l.href}>
                  {l.label}
                </a>
              ),
            )}
          </nav>

          <a className="nav-cta" href="/#contact">
            Get in touch
          </a>

          <button
            type="button"
            className="nav-toggle"
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? 'Close menu' : 'Open menu'}
            onClick={() => setOpen((v) => !v)}
          >
            <span />
            <span />
            <span />
          </button>
        </div>
      </header>

      <div
        id="mobile-nav"
        className={`nav-drawer${open ? ' is-open' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label="Mobile navigation"
        hidden={!open}
      >
        <nav aria-label="Mobile">
          {HOME_LINKS.map((l) =>
            'route' in l && l.route ? (
              <Link key={l.href} to="/products" onClick={close}>
                {l.label}
              </Link>
            ) : (
              <a key={l.href} href={l.href} onClick={close}>
                {l.label}
              </a>
            ),
          )}
        </nav>
      </div>
    </>
  )
}
