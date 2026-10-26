import { About } from './components/About'
import { Approach } from './components/Approach'
import { Contact } from './components/Contact'
import { Footer } from './components/Footer'
import { Hero } from './components/Hero'
import { Nav } from './components/Nav'
import { Pillars } from './components/Pillars'

export default function App() {
  return (
    <>
      <div className="atmosphere" aria-hidden="true" />
      <div className="grain" aria-hidden="true" />
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav />
      <main id="main">
        <Hero />
        <hr className="divider" />
        <About />
        <hr className="divider" />
        <Pillars />
        <hr className="divider" />
        <Approach />
        <hr className="divider" />
        <Contact />
      </main>
      <Footer />
    </>
  )
}
