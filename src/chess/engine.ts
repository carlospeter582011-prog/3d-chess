// Stockfish 19 (lite, single-thread WASM) wrapper. Runs fully on-device in a Web Worker.
// Needs no server, no SharedArrayBuffer and no special headers -> works offline as a PWA.

export interface Candidate { move: string; cp: number }

export const ELO_MIN = 400
export const ELO_MAX = 3200
const SF_MIN = 1320 // lowest Elo Stockfish's UCI_LimitStrength supports
const SF_MAX = 3190

export interface BotSettings {
  limitStrength: boolean
  uciElo: number
  movetime: number
  multiPV: number
  /** extra human-like mistakes for Elo below Stockfish's own minimum */
  weakness: number
}

/** Map a target Elo to engine settings. */
export function settingsForElo(elo: number): BotSettings {
  const e = Math.max(ELO_MIN, Math.min(ELO_MAX, Math.round(elo)))
  if (e >= SF_MIN) {
    if (e > SF_MAX) return { limitStrength: false, uciElo: SF_MAX, movetime: 1500, multiPV: 1, weakness: 0 }
    const movetime = Math.round(400 + ((e - SF_MIN) / (SF_MAX - SF_MIN)) * 1100)
    return { limitStrength: true, uciElo: e, movetime, multiPV: 1, weakness: 0 }
  }
  // below 1320: weakest Stockfish + shallow search + a growing chance of picking a worse move
  const weakness = (SF_MIN - e) / (SF_MIN - ELO_MIN) // 0..1
  return { limitStrength: true, uciElo: SF_MIN, movetime: 120, multiPV: 6, weakness }
}

/** Choose among MultiPV candidates; the weaker the bot, the more it drifts down the list. */
export function pickCandidate(cands: Candidate[], weakness: number, rnd: () => number = Math.random): string {
  if (cands.length === 1 || weakness <= 0) return cands[0].move
  const sorted = [...cands].sort((a, b) => b.cp - a.cp)
  // probability of deviating from the best move
  if (rnd() > 0.15 + 0.8 * weakness) return sorted[0].move
  // weights favour better moves but give worse ones a chance, flattening with weakness
  const tau = 0.6 + 3.5 * weakness
  const w = sorted.map((_, i) => Math.exp(-i / tau))
  const sum = w.reduce((a, b) => a + b, 0)
  let r = rnd() * sum
  for (let i = 0; i < w.length; i++) { r -= w[i]; if (r <= 0) return sorted[i].move }
  return sorted[0].move
}

interface Pending {
  resolve: (m: string | null) => void
  cands: Map<number, Candidate>
  weakness: number
}

export class Engine {
  private worker: Worker | null = null
  private listeners = new Set<(line: string) => void>()
  private ready: Promise<void> | null = null
  private pending: Pending | null = null
  private chain: Promise<unknown> = Promise.resolve()
  private newGameNeeded = true
  private optionLimits: { eloMin?: number; eloMax?: number } = {}

  private url() {
    return new URL(`${import.meta.env.BASE_URL}engine/stockfish-19-lite-single.js`, document.baseURI).href
  }

  private send(cmd: string) { this.worker?.postMessage(cmd) }

  private waitFor(test: (l: string) => boolean, timeoutMs = 20000): Promise<string> {
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => { this.listeners.delete(fn); reject(new Error('engine timeout')) }, timeoutMs)
      const fn = (l: string) => { if (test(l)) { clearTimeout(t); this.listeners.delete(fn); resolve(l) } }
      this.listeners.add(fn)
    })
  }

  init(): Promise<void> {
    if (this.ready) return this.ready
    this.ready = (async () => {
      this.worker = new Worker(this.url())
      this.worker.onmessage = (ev: MessageEvent) => {
        const line = typeof ev.data === 'string' ? ev.data : String(ev.data)
        this.onLine(line)
        for (const l of [...this.listeners]) l(line)
      }
      this.worker.onerror = (e) => console.error('[engine]', e.message)
      const uciok = this.waitFor((l) => l === 'uciok', 60000)
      const lines: string[] = []
      const collect = (l: string) => lines.push(l)
      this.listeners.add(collect)
      this.send('uci')
      await uciok
      this.listeners.delete(collect)
      const elo = lines.find((l) => l.includes('name UCI_Elo '))
      if (elo) {
        const mn = /min (\d+)/.exec(elo), mx = /max (\d+)/.exec(elo)
        this.optionLimits = { eloMin: mn ? +mn[1] : undefined, eloMax: mx ? +mx[1] : undefined }
      }
      await this.isReady()
    })()
    return this.ready
  }

  private async isReady() {
    const p = this.waitFor((l) => l === 'readyok')
    this.send('isready')
    await p
  }

  private onLine(line: string) {
    const p = this.pending
    if (!p) return
    if (line.startsWith('info ') && line.includes(' pv ')) {
      const mpv = /multipv (\d+)/.exec(line)
      const idx = mpv ? +mpv[1] : 1
      const cp = /score cp (-?\d+)/.exec(line)
      const mate = /score mate (-?\d+)/.exec(line)
      const pv = / pv (\S+)/.exec(line)
      if (pv && (cp || mate)) {
        const score = cp ? +cp[1] : (+mate![1] > 0 ? 100000 - +mate![1] : -100000 - +mate![1])
        p.cands.set(idx, { move: pv[1], cp: score })
      }
    } else if (line.startsWith('bestmove')) {
      const m = /bestmove (\S+)/.exec(line)
      const best = m && m[1] !== '(none)' ? m[1] : null
      this.pending = null
      let chosen = best
      if (best && p.cands.size > 1) {
        const list = [...p.cands.values()]
        chosen = pickCandidate(list, p.weakness)
      }
      p.resolve(chosen)
    }
  }

  /** Ask for a move (UCI long algebraic, e.g. "e2e4" or "e7e8q"). Resolves null if cancelled / no move. */
  bestMove(fen: string, elo: number): Promise<string | null> {
    const run = async (): Promise<string | null> => {
      await this.init()
      const s = settingsForElo(elo)
      if (this.newGameNeeded) { this.send('ucinewgame'); this.newGameNeeded = false }
      this.send(`setoption name MultiPV value ${s.multiPV}`)
      this.send(`setoption name UCI_LimitStrength value ${s.limitStrength}`)
      if (s.limitStrength) {
        const lo = this.optionLimits.eloMin ?? 1320, hi = this.optionLimits.eloMax ?? 3190
        this.send(`setoption name UCI_Elo value ${Math.max(lo, Math.min(hi, s.uciElo))}`)
      }
      await this.isReady()
      this.send(`position fen ${fen}`)
      const result = new Promise<string | null>((resolve) => {
        this.pending = { resolve, cands: new Map(), weakness: s.weakness }
      })
      this.send(s.weakness > 0 ? `go depth ${1 + Math.round((1 - s.weakness) * 3)} movetime ${s.movetime}` : `go movetime ${s.movetime}`)
      return result
    }
    // serialise requests
    const p = this.chain.then(run, run)
    this.chain = p.catch(() => null)
    return p
  }

  /** Abort the current search; the pending promise resolves with whatever Stockfish returns (caller ignores it). */
  stop() { if (this.pending) this.send('stop') }

  resetGame() { this.newGameNeeded = true }

  terminate() { this.worker?.terminate(); this.worker = null; this.ready = null; this.pending = null }
}
