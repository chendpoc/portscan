const BY_NAME: Record<string, string> = {
  ollama: 'glyph-ollama.svg',
  node: 'glyph-node-a.svg',
  python3: 'glyph-python.svg',
  python: 'glyph-python.svg',
  postgres: 'glyph-postgres.svg',
  redis: 'glyph-redis.svg',
  cursor: 'glyph-cursor.svg',
  windowserver: 'glyph-windowserver.svg',
}

const FALLBACKS = [
  'glyph-node-a.svg',
  'glyph-node-b.svg',
  'glyph-python.svg',
  'glyph-postgres.svg',
  'glyph-redis.svg',
  'glyph-cursor.svg',
  'glyph-ollama.svg',
]

export function processGlyphUrl(name: string, pid: number, cwdPath?: string | null): string {
  const key = name.toLowerCase()
  if (key === 'node' && cwdPath?.includes('web-ui')) return '/figma/glyphs/glyph-node-b.svg'
  if (key === 'node' && cwdPath?.includes('api-red')) return '/figma/glyphs/glyph-node-a.svg'
  const mapped = BY_NAME[key]
  if (mapped) return `/figma/glyphs/${mapped}`
  return `/figma/glyphs/${FALLBACKS[pid % FALLBACKS.length]}`
}
