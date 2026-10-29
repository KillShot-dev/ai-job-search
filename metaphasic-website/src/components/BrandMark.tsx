type Props = {
  className?: string
  size?: number
  alt?: string
}

/** Interlocking ribbon mark — transparent PNG for dark UI. */
export function BrandMark({ className = '', size = 36, alt = '' }: Props) {
  return (
    <img
      className={`brand-mark ${className}`.trim()}
      src="/assets/metaphasic-mark.png"
      width={size}
      height={size}
      alt={alt}
      decoding="async"
    />
  )
}
