import type { CSSProperties, ReactNode } from 'react'
import { useReveal } from '../hooks/useReveal'

type Variant = 'up' | 'left' | 'scale'

type Props = {
  children: ReactNode
  className?: string
  delay?: number
  variant?: Variant
  as?: 'div' | 'section' | 'article' | 'li' | 'header'
  id?: string
}

const variantClass: Record<Variant, string> = {
  up: '',
  left: 'reveal-left',
  scale: 'reveal-scale',
}

export function Reveal({
  children,
  className = '',
  delay = 0,
  variant = 'up',
  as: Tag = 'div',
  id,
}: Props) {
  const ref = useReveal<HTMLDivElement>()
  const style = { '--delay': `${delay}ms` } as CSSProperties

  return (
    <Tag
      ref={ref as never}
      id={id}
      className={`reveal ${variantClass[variant]} ${className}`.trim()}
      style={style}
    >
      {children}
    </Tag>
  )
}
