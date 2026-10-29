export type MarqueeItem = {
  label: string
  href?: string
}

type Props = {
  items: Array<string | MarqueeItem>
  label?: string
}

function normalize(item: string | MarqueeItem): MarqueeItem {
  return typeof item === 'string' ? { label: item } : item
}

/** Infinite editorial ticker — optional per-item anchor links. */
export function Marquee({ items, label = 'Marquee' }: Props) {
  const normalized = items.map(normalize)
  const row = [...normalized, ...normalized]

  return (
    <div className="marquee" aria-label={label}>
      <div className="marquee-track">
        {row.map((item, i) => (
          <span key={`${item.label}-${i}`} className="marquee-item">
            <span className="marquee-dot" aria-hidden="true" />
            {item.href ? (
              <a className="marquee-link" href={item.href}>
                {item.label}
              </a>
            ) : (
              item.label
            )}
          </span>
        ))}
      </div>
    </div>
  )
}
