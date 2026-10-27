import type { CSSProperties, ReactNode } from 'react'
import { useReveal } from '../hooks/useReveal'

type Variant = 'up' | 'left' | 'scale' | 'clip' | 'blur'

type Props = {
  children: ReactNode
  className?: string
  delay?: number
  variant?: Variant
  as?: 'div' | 'section' | 'article' | 'li' | 'header'
  id?: string
  /** Stagger direct children with data-stagger */
  stagger?: boolean
}

const variantClass: Record<Variant, string> = {
  up: '',
  left: 'reveal-left',
  scale: 'reveal-scale',
  clip: 'reveal-clip',
  blur: 'reveal-blur',
}

export function Reveal({
  children,
  className = '',
  delay = 0,
  variant = 'up',
  as: Tag = 'div',
  id,
  stagger = false,
}: Props) {
  const ref = useReveal<HTMLDivElement>()
  const style = { '--delay': `${delay}ms` } as CSSProperties

  return (
    <Tag
      ref={ref as never}
      id={id}
      className={`reveal ${variantClass[variant]} ${stagger ? 'reveal-stagger' : ''} ${className}`.trim()}
      style={style}
    >
      {children}
    </Tag>
  )
}
