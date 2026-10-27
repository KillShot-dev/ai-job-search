import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useEffect } from 'react'
import { Cursor } from './components/Cursor'
import { Footer } from './components/Footer'
import { Nav } from './components/Nav'
import { ScrollProgress } from './components/ScrollProgress'
import { HomePage } from './pages/HomePage'
import { ProductsPage } from './pages/ProductsPage'

function ScrollManager() {
  const { pathname, hash } = useLocation()

  useEffect(() => {
    if (hash) {
      const id = hash.replace('#', '')
      requestAnimationFrame(() => {
        const el = document.getElementById(id)
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' })
      })
      return
    }
    window.scrollTo(0, 0)
  }, [pathname, hash])

  return null
}

export default function App() {
  return (
    <>
      <div className="atmosphere" aria-hidden="true" />
      <div className="grain" aria-hidden="true" />
      <ScrollProgress />
      <Cursor />
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav />
      <ScrollManager />
      <main id="main">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/products" element={<ProductsPage />} />
          <Route path="/apps" element={<Navigate to="/products" replace />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      <Footer />
    </>
  )
}
