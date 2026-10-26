import { useEffect, useState } from 'react'
import { useNavScroll } from '../hooks/useNavScroll'

const LINKS = [
  { href: '#about', label: 'Firm' },
  { href: '#investments', label: 'Investments' },
  { href: '#development', label: 'Development' },
  { href: '#asset-management', label: 'Asset Management' },
  { href: '#approach', label: 'Approach' },
  { href: '#contact', label: 'Contact' },
]

export function Nav() {
  const scrolled = useNavScroll()
  const [open, setOpen] = useState(false)

  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => {
      document.body.style.overflow = ''
    }
  }, [open])

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
          <a className="brand" href="#top" onClick={close} aria-label="metaPhasic Group home">
            metaPhasic <span>Group</span>
          </a>

          <nav className="nav-links" aria-label="Primary">
            {LINKS.map((l) => (
              <a key={l.href} href={l.href}>
                {l.label}
              </a>
            ))}
          </nav>

          <a className="nav-cta" href="#contact">
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
          {LINKS.map((l) => (
            <a key={l.href} href={l.href} onClick={close}>
              {l.label}
            </a>
          ))}
        </nav>
      </div>
    </>
  )
}
