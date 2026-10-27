type Props = {
  items: string[]
  label?: string
}

/** Infinite editorial ticker — technique adapted from Site of Sites–style agency marquees. */
export function Marquee({ items, label = 'Marquee' }: Props) {
  const row = [...items, ...items]

  return (
    <div className="marquee" role="presentation" aria-label={label}>
      <div className="marquee-track">
        {row.map((item, i) => (
          <span key={`${item}-${i}`} className="marquee-item">
            <span className="marquee-dot" aria-hidden="true" />
            {item}
          </span>
        ))}
      </div>
    </div>
  )
}
