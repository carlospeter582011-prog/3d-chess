// Downloads each 3D model once, stores it in the Cache Storage and serves it from there afterwards,
// so the game works with no internet after the first launch.
export const MODEL_CACHE = 'chess3d-models-v1'

export const MODEL_FILES = [
  'board',
  'king_light', 'king_dark', 'queen_light', 'queen_dark', 'bishop_light', 'bishop_dark',
  'knight_light', 'knight_dark', 'rook_light', 'rook_dark', 'pawn_light', 'pawn_dark',
] as const

export function modelUrl(name: string) {
  return new URL(`${import.meta.env.BASE_URL}models/${name}.glb`, document.baseURI).href
}

export interface LoadProgress { loaded: number; total: number; fromCache: boolean }

async function openCache(): Promise<Cache | null> {
  try { return 'caches' in self ? await caches.open(MODEL_CACHE) : null } catch { return null }
}

/** Fetch with byte-level progress. */
async function fetchWithProgress(url: string, onBytes: (n: number) => void): Promise<{ buf: ArrayBuffer; response: Response }> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`Failed to load ${url}: ${res.status}`)
  const reader = res.clone().body?.getReader()
  if (!reader) {
    const buf = await res.arrayBuffer(); onBytes(buf.byteLength); return { buf, response: res }
  }
  const chunks: Uint8Array[] = []
  let size = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    chunks.push(value); size += value.byteLength; onBytes(value.byteLength)
  }
  const out = new Uint8Array(size); let o = 0
  for (const c of chunks) { out.set(c, o); o += c.byteLength }
  return { buf: out.buffer, response: res }
}

export async function loadModelBuffer(name: string, onBytes: (n: number, fromCache: boolean) => void): Promise<ArrayBuffer> {
  const url = modelUrl(name)
  const cache = await openCache()
  if (cache) {
    const hit = await cache.match(url)
    if (hit) { const buf = await hit.arrayBuffer(); onBytes(buf.byteLength, true); return buf }
  }
  const { buf, response } = await fetchWithProgress(url, (n) => onBytes(n, false))
  if (cache) { try { await cache.put(url, new Response(buf, { headers: response.headers })) } catch { /* quota */ } }
  return buf
}

export async function isFullyCached(): Promise<boolean> {
  const cache = await openCache()
  if (!cache) return false
  for (const n of MODEL_FILES) if (!(await cache.match(modelUrl(n)))) return false
  return true
}

export async function requestPersistentStorage() {
  try { await navigator.storage?.persist?.() } catch { /* ignore */ }
}
