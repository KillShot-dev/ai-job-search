import { About } from '../components/About'
import { Approach } from '../components/Approach'
import { Contact } from '../components/Contact'
import { Hero } from '../components/Hero'
import { Marquee } from '../components/Marquee'
import { Pillars } from '../components/Pillars'

const LUMA_FINISHES = [
  'Luma Regular',
  'Luma Dark',
  'Luma Gradient',
  'Luma Glyph',
  'Luma Clear',
  'Luma Prism',
  'Luma Midnight',
]

export function HomePage() {
  return (
    <>
      <Hero />
      <Marquee items={LUMA_FINISHES} label="Luma finishes" />
      <hr className="divider divider-animated" />
      <About />
      <hr className="divider divider-animated" />
      <Pillars />
      <Marquee items={['Design', 'Engineering', 'Consulting', 'Icon packs', 'Product strategy']} label="Capabilities" />
      <hr className="divider divider-animated" />
      <Approach />
      <hr className="divider divider-animated" />
      <Contact />
    </>
  )
}
