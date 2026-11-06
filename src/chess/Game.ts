import { Chess } from 'chess.js'
import type { Move, Square } from 'chess.js'
import { Board3D } from '../three/Board3D'
import type { Color, PType, PlacedPiece } from '../three/Board3D'
import { Engine } from './engine'
import { sfx, setMuted } from './sound'

export type Mode = 'bot' | 'local'
export type Status = 'playing' | 'checkmate' | 'stalemate' | 'draw' | 'resigned'

export interface GameConfig { mode: Mode; humanColor: Color; elo: number }

export interface GameSnapshot {
  version: number
  active: boolean
  config: GameConfig
  fen: string
  turn: Color
  history: string[]
  status: Status
  reason: string
  winner: Color | null
  check: boolean
  thinking: boolean
  busy: boolean
  selected: string | null
  promotion: { from: string; to: string } | null
  captured: { w: PType[]; b: PType[] } // pieces each side has lost
  canUndo: boolean
  engineError: boolean
}

const SAVE_KEY = 'chess3d-save-v1'
const SETTINGS_KEY = 'chess3d-settings-v1'

export interface Settings { sound: boolean; labels: boolean; quality: 'high' | 'low'; autoFlip: boolean; elo: number; humanColor: Color | 'r'; mode: Mode }
export const defaultSettings: Settings = { sound: true, labels: true, quality: 'high', autoFlip: false, elo: 1200, humanColor: 'w', mode: 'bot' }

export function loadSettings(): Settings {
  try { return { ...defaultSettings, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') } } catch { return { ...defaultSettings } }
}
export function saveSettings(s: Settings) { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(s)) } catch { /* ignore */ } }

const emptyConfig: GameConfig = { mode: 'bot', humanColor: 'w', elo: 1200 }

export class Game {
  chess = new Chess()
  board: Board3D
  engine = new Engine()
  config: GameConfig = { ...emptyConfig }
  private listeners = new Set<() => void>()
  private snap!: GameSnapshot
  private version = 0
  private active = false
  private selected: Square | null = null
  private promotion: { from: Square; to: Square } | null = null
  private thinking = false
  private busy = false
  private epoch = 0
  private resigned: Color | null = null // colour that resigned
  private agreedDraw = false
  private engineError = false
  autoFlip = false

  constructor(board: Board3D) {
    this.board = board
    this.refresh()
  }

  // ---- store plumbing
  subscribe = (fn: () => void) => { this.listeners.add(fn); return () => { this.listeners.delete(fn) } }
  getSnapshot = () => this.snap
  private refresh() {
    const history = this.chess.history({ verbose: true })
    const captured = { w: [] as PType[], b: [] as PType[] }
    for (const m of history) if (m.captured) captured[m.color === 'w' ? 'b' : 'w'].push(m.captured as PType)
    const st = this.computeStatus()
    this.snap = {
      version: ++this.version,
      active: this.active,
      config: this.config,
      fen: this.chess.fen(),
      turn: this.chess.turn(),
      history: history.map((m) => m.san),
      status: st.status,
      reason: st.reason,
      winner: st.winner,
      check: this.chess.isCheck(),
      thinking: this.thinking,
      busy: this.busy,
      selected: this.selected,
      promotion: this.promotion,
      captured,
      canUndo: history.length > 0 && !this.busy && st.status !== 'resigned',
      engineError: this.engineError,
    }
    for (const l of this.listeners) l()
  }

  private computeStatus(): { status: Status; reason: string; winner: Color | null } {
    const c = this.chess
    if (this.resigned) return { status: 'resigned', reason: `${this.resigned === 'w' ? 'White' : 'Black'} resigned`, winner: this.resigned === 'w' ? 'b' : 'w' }
    if (this.agreedDraw) return { status: 'draw', reason: 'Draw agreed', winner: null }
    if (c.isCheckmate()) return { status: 'checkmate', reason: 'Checkmate', winner: c.turn() === 'w' ? 'b' : 'w' }
    if (c.isStalemate()) return { status: 'stalemate', reason: 'Stalemate', winner: null }
    if (c.isInsufficientMaterial()) return { status: 'draw', reason: 'Insufficient material', winner: null }
    if (c.isThreefoldRepetition()) return { status: 'draw', reason: 'Threefold repetition', winner: null }
    if (c.isDrawByFiftyMoves()) return { status: 'draw', reason: 'Fifty-move rule', winner: null }
    return { status: 'playing', reason: '', winner: null }
  }

  // ---- lifecycle
  setSettings(s: Settings) {
    this.autoFlip = s.autoFlip
    setMuted(!s.sound)
    this.board.setLabelsVisible(s.labels)
  }

  placed(): PlacedPiece[] {
    const out: PlacedPiece[] = []
    for (const row of this.chess.board()) for (const p of row) if (p) out.push({ square: p.square, color: p.color, type: p.type as PType })
    return out
  }

  syncBoard() {
    this.board.setPosition(this.placed())
    this.updateMarkers()
  }

  start(cfg: GameConfig, opts: { pgn?: string } = {}) {
    this.cancelThinking()
    this.config = { ...cfg }
    this.chess = new Chess()
    if (opts.pgn) { try { this.chess.loadPgn(opts.pgn) } catch { this.chess = new Chess() } }
    this.resigned = null; this.agreedDraw = false; this.selected = null; this.promotion = null
    this.busy = false; this.engineError = false; this.active = true
    this.engine.resetGame()
    this.syncBoard()
    const side: Color = cfg.mode === 'bot' ? cfg.humanColor : this.chess.turn()
    this.board.controls.autoRotate = false
    this.board.resetCamera(true, side)
    this.refresh()
    this.save()
    void this.maybeBotMove()
  }

  /** Back to the menu without losing the game. */
  leave() {
    this.cancelThinking()
    this.active = false
    this.refresh()
  }

  resume() {
    this.active = true
    this.refresh()
    void this.maybeBotMove()
  }

  save() {
    try {
      if (this.chess.history().length === 0 && !this.active) return
      const over = this.computeStatus().status !== 'playing'
      if (over) { localStorage.removeItem(SAVE_KEY); return }
      localStorage.setItem(SAVE_KEY, JSON.stringify({ config: this.config, pgn: this.chess.pgn() }))
    } catch { /* ignore */ }
  }
  static loadSaved(): { config: GameConfig; pgn: string } | null {
    try { const s = JSON.parse(localStorage.getItem(SAVE_KEY) || 'null'); return s && s.config && typeof s.pgn === 'string' ? s : null } catch { return null }
  }
  static clearSaved() { try { localStorage.removeItem(SAVE_KEY) } catch { /* ignore */ } }

  private cancelThinking() {
    this.epoch++
    if (this.thinking) this.engine.stop()
    this.thinking = false
  }

  // ---- input
  private isHumanTurn() {
    return this.config.mode === 'local' || this.chess.turn() === this.config.humanColor
  }

  legalFrom(sq: Square): Move[] { return this.chess.moves({ square: sq, verbose: true }) }

  tap(sq: string, ground: string | null = null) {
    if (!this.active || this.busy || this.promotion) return
    if (this.computeStatus().status !== 'playing' || !this.isHumanTurn()) return
    // A tall piece can hide the square behind it. If a piece is selected and the tap landed on a piece that
    // is not a legal destination (e.g. the selected piece itself) while the floor under the finger IS one, move there.
    if (this.selected && ground && ground !== sq) {
      const legal = this.legalFrom(this.selected)
      const hit = this.chess.get(sq as Square)
      const ownOther = !!hit && hit.color === this.chess.turn() && sq !== this.selected
      if (!legal.some((m) => m.to === sq) && legal.some((m) => m.to === ground) && !ownOther) sq = ground
    }
    const square = sq as Square
    const piece = this.chess.get(square)
    if (this.selected) {
      const mv = this.legalFrom(this.selected).find((m) => m.to === square)
      if (mv) {
        if (mv.isPromotion()) {
          this.promotion = { from: this.selected, to: square }
          this.refresh()
          return
        }
        void this.playMove(this.selected, square)
        return
      }
      if (piece && piece.color === this.chess.turn() && square !== this.selected) { this.select(square); return }
      this.deselect(); return
    }
    if (piece && piece.color === this.chess.turn()) this.select(square)
  }

  private select(sq: Square) {
    this.selected = sq
    this.board.lift(sq)
    this.updateMarkers()
    this.refresh()
  }
  private deselect() {
    this.selected = null
    this.board.unlift()
    this.updateMarkers()
    this.refresh()
  }

  choosePromotion(p: 'q' | 'r' | 'b' | 'n') {
    if (!this.promotion) return
    const { from, to } = this.promotion
    this.promotion = null
    void this.playMove(from, to, p)
  }
  cancelPromotion() {
    this.promotion = null
    this.deselect()
  }

  private updateMarkers() {
    const hist = this.chess.history({ verbose: true })
    const last = hist.length ? hist[hist.length - 1] : null
    const targets = this.selected ? this.legalFrom(this.selected).map((m) => ({ sq: m.to, capture: !!m.captured })) : []
    let check: string | null = null
    if (this.chess.isCheck()) {
      const t = this.chess.turn()
      for (const row of this.chess.board()) for (const p of row) if (p && p.type === 'k' && p.color === t) check = p.square
    }
    this.board.setMarkers({ selected: this.selected, targets, last: last ? [last.from, last.to] : null, check })
  }

  // ---- moves
  async playMove(from: string, to: string, promotion?: 'q' | 'r' | 'b' | 'n'): Promise<Move> {
    this.busy = true
    this.selected = null
    const mv = this.chess.move({ from, to, promotion })
    this.board.setMarkers({ last: [mv.from, mv.to] })
    this.refresh()
    const jobs: Promise<void>[] = []
    const capSq = mv.isEnPassant() ? to[0] + from[1] : mv.captured ? to : undefined
    jobs.push(this.board.movePiece(from, to, { capture: capSq, promotion: promotion as PType | undefined }))
    if (mv.isKingsideCastle()) jobs.push(this.board.movePiece('h' + from[1], 'f' + from[1]))
    if (mv.isQueensideCastle()) jobs.push(this.board.movePiece('a' + from[1], 'd' + from[1]))
    if (mv.captured) sfx.capture(); else sfx.move()
    await Promise.all(jobs)
    this.busy = false
    this.updateMarkers()
    const st = this.computeStatus()
    if (st.status !== 'playing') sfx.end(); else if (this.chess.isCheck()) sfx.check()
    this.refresh()
    this.save()
    if (st.status === 'playing') {
      if (this.config.mode === 'local' && this.autoFlip) this.board.resetCamera(true, this.chess.turn())
      void this.maybeBotMove()
    }
    return mv
  }

  private async maybeBotMove() {
    if (!this.active || this.config.mode !== 'bot') return
    if (this.computeStatus().status !== 'playing') return
    if (this.chess.turn() === this.config.humanColor) return
    const token = ++this.epoch
    this.thinking = true
    this.refresh()
    const started = performance.now()
    let uci: string | null = null
    try {
      uci = await this.engine.bestMove(this.chess.fen(), this.config.elo)
    } catch (e) {
      console.error('engine failed, falling back to a random move', e)
      this.engineError = true
    }
    if (token !== this.epoch) return // cancelled (undo / new game / leave)
    const legal = this.chess.moves({ verbose: true })
    let mv = uci ? legal.find((m) => m.from + m.to + (m.promotion ?? '') === uci) : undefined
    if (!mv) mv = legal[Math.floor(Math.random() * legal.length)]
    if (!mv) { this.thinking = false; this.refresh(); return }
    const wait = 450 - (performance.now() - started)
    if (wait > 0) await new Promise((r) => setTimeout(r, wait))
    if (token !== this.epoch) return
    this.thinking = false
    await this.playMove(mv.from, mv.to, mv.promotion as 'q' | 'r' | 'b' | 'n' | undefined)
  }

  // ---- game actions
  undo() {
    if (this.busy || this.chess.history().length === 0 || this.resigned) return
    this.cancelThinking()
    this.agreedDraw = false
    this.chess.undo()
    if (this.config.mode === 'bot' && this.chess.turn() !== this.config.humanColor && this.chess.history().length > 0) this.chess.undo()
    this.selected = null; this.promotion = null
    this.syncBoard()
    this.refresh()
    this.save()
    if (this.config.mode === 'local' && this.autoFlip) this.board.resetCamera(true, this.chess.turn())
    void this.maybeBotMove()
  }

  resign() {
    if (this.computeStatus().status !== 'playing') return
    this.cancelThinking()
    this.resigned = this.config.mode === 'bot' ? this.config.humanColor : this.chess.turn()
    this.selected = null; this.promotion = null
    this.board.unlift(); this.updateMarkers()
    this.refresh(); this.save(); sfx.end()
  }

  agreeDraw() {
    if (this.computeStatus().status !== 'playing') return
    this.cancelThinking()
    this.agreedDraw = true
    this.selected = null; this.board.unlift(); this.updateMarkers()
    this.refresh(); this.save(); sfx.end()
  }

  /** Developer / test hook: jump to an arbitrary position. */
  debugLoadFen(fen: string) {
    this.cancelThinking()
    this.chess = new Chess(fen)
    this.selected = null; this.promotion = null; this.busy = false; this.resigned = null; this.agreedDraw = false
    this.syncBoard()
    this.refresh()
  }

  get currentStatus() { return this.computeStatus() }
}
