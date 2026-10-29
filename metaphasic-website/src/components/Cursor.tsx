import { useEffect, useState } from 'react'

/** Dual-element custom cursor (dot + lagged ring). Desktop fine-pointer only. */
export function Cursor() {
  const [enabled, setEnabled] = useState(false)
  const [pos, setPos] = useState({ x: 0, y: 0 })
  const [ring, setRing] = useState({ x: 0, y: 0 })
  const [hovering, setHovering] = useState(false)

  useEffect(() => {
    const fine = window.matchMedia('(pointer: fine)').matches
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (!fine || reduce) return
    setEnabled(true)

    let rx = 0
    let ry = 0
    let tx = 0
    let ty = 0
    let raf = 0

    const onMove = (e: MouseEvent) => {
      tx = e.clientX
      ty = e.clientY
      setPos({ x: tx, y: ty })
    }

    const tick = () => {
      rx += (tx - rx) * 0.18
      ry += (ty - ry) * 0.18
      setRing({ x: rx, y: ry })
      raf = requestAnimationFrame(tick)
    }

    const onOver = (e: MouseEvent) => {
      const t = e.target as HTMLElement | null
      const interactive = t?.closest('a, button, .app-card, .btn, .pillar')
      setHovering(Boolean(interactive))
    }

    window.addEventListener('mousemove', onMove, { passive: true })
    document.addEventListener('mouseover', onOver, { passive: true })
    raf = requestAnimationFrame(tick)
    document.documentElement.classList.add('has-custom-cursor')

    return () => {
      window.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseover', onOver)
      cancelAnimationFrame(raf)
      document.documentElement.classList.remove('has-custom-cursor')
    }
  }, [])

  if (!enabled) return null

  return (
    <>
      <div
        className={`cursor-dot${hovering ? ' is-hover' : ''}`}
        style={{ transform: `translate3d(${pos.x}px, ${pos.y}px, 0)` }}
        aria-hidden="true"
      />
      <div
        className={`cursor-ring${hovering ? ' is-hover' : ''}`}
        style={{ transform: `translate3d(${ring.x}px, ${ring.y}px, 0)` }}
        aria-hidden="true"
      />
    </>
  )
}
