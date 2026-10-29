import { useEffect, useRef } from 'react'

/** Intersection Observer scroll reveal — lean Apple/Awwwards-style entrance. */
export function useReveal<T extends HTMLElement>(options?: IntersectionObserverInit) {
  const ref = useRef<T>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return

    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduce) {
      el.classList.add('is-visible')
      return
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          el.classList.add('is-visible')
          observer.unobserve(el)
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -8% 0px', ...options },
    )

    observer.observe(el)
    return () => observer.disconnect()
  }, [options])

  return ref
}
