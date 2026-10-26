import { About } from '../components/About'
import { Approach } from '../components/Approach'
import { Contact } from '../components/Contact'
import { Hero } from '../components/Hero'
import { Pillars } from '../components/Pillars'

export function HomePage() {
  return (
    <>
      <Hero />
      <hr className="divider" />
      <About />
      <hr className="divider" />
      <Pillars />
      <hr className="divider" />
      <Approach />
      <hr className="divider" />
      <Contact />
    </>
  )
}
