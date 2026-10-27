import type { ReactNode } from 'react'
import { useMagnetic } from '../hooks/useMagnetic'

type Props = {
  children: ReactNode
  className?: string
  strength?: number
}

export function Magnetic({ children, className = '', strength = 0.28 }: Props) {
  const ref = useMagnetic<HTMLDivElement>(strength)
  return (
    <div ref={ref} className={`magnetic ${className}`.trim()}>
      {children}
    </div>
  )
}
