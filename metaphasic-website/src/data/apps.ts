/** Luma icon pack collection — copy adapted from Play Console description.txt files. */
export type AppEntry = {
  id: string
  slot: string
  name: string
  finish: string
  packageId: string
  price: string
  tagline: string
  description: string
  highlights: string[]
  screenshot: string
  storeLabel: string
  storeUrl: string
  accent: string
}

const play = (packageId: string) =>
  `https://play.google.com/store/apps/details?id=${packageId}`

/** Generic Play home until the developer listing / packs are live — swap later. */
export const PLAY_STORE_HOME = 'https://play.google.com/store'

const SHARED_HIGHLIGHTS = [
  '315 icons as one family',
  'Dashboard, wallpapers, and Luma widgets',
  'Requires a custom launcher that supports icon packs',
]

export const APPS: AppEntry[] = [
  {
    id: 'luma-regular',
    slot: '01',
    name: 'Luma — Regular',
    finish: 'Regular',
    packageId: 'com.metaphasicgroup.luma.regular',
    price: '$2.49',
    tagline: 'Light, colorful icons with restraint. 315 icons, one calm look.',
    description:
      'Color, with restraint. Luma Regular is the light, colorful set: pale luminous squircle tiles in restrained tints, white glyphs, and a soft top gloss. Colour is present but never loud — the default “home screen, considered” look.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/01-luma-regular.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.regular'),
    accent: '#c8d8f0',
  },
  {
    id: 'luma-dark',
    slot: '02',
    name: 'Luma — Dark',
    finish: 'Dark',
    packageId: 'com.metaphasicgroup.luma.dark',
    price: '$2.49',
    tagline: 'Deep slate squircles, white glyphs. 315 icons for a quieter home.',
    description:
      'Quiet depth. Luma Dark keeps the same squircle family as Regular, shifted into deep slate and charcoal tiles with white glyphs and restrained gloss — built for dark homescreens that still feel coherent, not muddy.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/02-luma-dark.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.dark'),
    accent: '#8a9bb0',
  },
  {
    id: 'luma-gradient',
    slot: '03',
    name: 'Luma — Gradient',
    finish: 'Gradient',
    packageId: 'com.metaphasicgroup.luma.gradient',
    price: '$2.49',
    tagline: 'Bold saturated gradient tiles. 315 icons, one vivid family.',
    description:
      'Saturation, on purpose. Luma Gradient uses bold diagonal tile gradients and white glyphs so everyday apps read as one vivid family instead of a scrapbook of logos.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/03-luma-gradient.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.gradient'),
    accent: '#e8a0c8',
  },
  {
    id: 'luma-glyph',
    slot: '04',
    name: 'Luma — Glyph',
    finish: 'Glyph',
    packageId: 'com.metaphasicgroup.luma.glyph',
    price: '$2.49',
    tagline: 'Colorful glyphs on clear ground — no tile mask. 315 icons.',
    description:
      'Marks without a mask. Luma Glyph ships logo-only color glyphs on transparent grounds — no squircle backplate — so launchers that prefer bare icons stay sharp and uncropped.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/04-luma-glyph.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.glyph'),
    accent: '#7ec8e8',
  },
  {
    id: 'luma-clear',
    slot: '05',
    name: 'Luma — Clear',
    finish: 'Clear',
    packageId: 'com.metaphasicgroup.luma.clear',
    price: '$2.49',
    tagline: 'Airy translucent squircles. 315 icons with a soft, open look.',
    description:
      'Light and open. Luma Clear softens the tile treatment into airy, translucent squircles with white glyphs — a quieter light finish for uncluttered home screens.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/05-luma-clear.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.clear'),
    accent: '#d0e4f8',
  },
  {
    id: 'luma-prism',
    slot: '06',
    name: 'Luma — Prism',
    finish: 'Prism',
    packageId: 'com.metaphasicgroup.luma.prism',
    price: '$2.49',
    tagline: 'Muted dusty gradients, bold white glyphs. 315 icons.',
    description:
      'Muted gradients, chunkier marks. Luma Prism keeps the gradient-tile + white-glyph language of Gradient, but in a dustier duotone palette with bolder glyphs for a calmer, more editorial look.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/06-luma-prism.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.prism'),
    accent: '#b8a0c8',
  },
  {
    id: 'luma-midnight',
    slot: '07',
    name: 'Luma — Midnight',
    finish: 'Midnight',
    packageId: 'com.metaphasicgroup.luma.midnight',
    price: '$2.49',
    tagline: 'Night-depth tiles and crisp glyphs. 315 icons after dark.',
    description:
      'After dark. Luma Midnight pushes the pack into night-depth tiles — near-black grounds, cool accents, crisp white glyphs — for launchers that live in OLED dark.',
    highlights: SHARED_HIGHLIGHTS,
    screenshot: '/assets/apps/07-luma-midnight.png',
    storeLabel: 'Get on Google Play',
    storeUrl: play('com.metaphasicgroup.luma.midnight'),
    accent: '#6a8ab0',
  },
]
