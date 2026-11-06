import { useEffect, useRef, useState } from 'react'
import type { Game, GameSnapshot } from '../chess/Game'
import type { Color, PType } from '../three/Board3D'
import { GLYPH, VALUE } from './glyphs'

function Captured({ lost, color }: { lost: PType[]; color: Color }) {
  const order: PType[] = ['q', 'r', 'b', 'n', 'p']
  const sorted = [...lost].sort((a, b) => order.indexOf(a) - order.indexOf(b))
  return <span className={`captured ${color === 'w' ? 'cw' : 'cb'}`} aria-label="captured pieces">{sorted.map((t, i) => <i key={i}>{GLYPH[t]}</i>)}</span>
}

function material(s: GameSnapshot, c: Color) {
  const gain = (lost: PType[]) => lost.reduce((a, t) => a + VALUE[t], 0)
  const mine = gain(s.captured[c === 'w' ? 'b' : 'w']) // what I captured = what the other side lost
  const theirs = gain(s.captured[c])
  return mine - theirs
}

function PlayerCard({ s, color, label, sub }: { s: GameSnapshot; color: Color; label: string; sub?: string }) {
  const lost = s.captured[color === 'w' ? 'b' : 'w'] // pieces this player has captured
  const diff = material(s, color)
  const active = s.status === 'playing' && s.turn === color
  return (
    <div className={`pcard ${active ? 'active' : ''}`}>
      <span className={`dot ${color === 'w' ? 'w' : 'b'}`} />
      <div className="pinfo">
        <b>{label}</b>
        {sub && <small>{sub}</small>}
      </div>
      <Captured lost={lost} color={color === 'w' ? 'b' : 'w'} />
      {diff > 0 && <em>+{diff}</em>}
    </div>
  )
}

export function Hud({ game, s, onMenu, onSettings }: { game: Game; s: GameSnapshot; onMenu: () => void; onSettings: () => void }) {
  const movesRef = useRef<HTMLDivElement>(null)
  const [topView, setTopView] = useState(false)
  const [confirm, setConfirm] = useState<null | 'resign' | 'draw' | 'new'>(null)
  const bot = s.config.mode === 'bot'
  const human = s.config.humanColor
  const opp: Color = bot ? (human === 'w' ? 'b' : 'w') : 'b'
  const me: Color = bot ? human : 'w'

  useEffect(() => { const el = movesRef.current; if (el) { el.scrollLeft = el.scrollWidth; el.scrollTop = el.scrollHeight } }, [s.history.length])

  let status = ''
  let tone = ''
  if (s.status !== 'playing') {
    tone = 'over'
    status = s.status === 'checkmate' ? `Checkmate · ${s.winner === 'w' ? 'White' : 'Black'} wins`
      : s.status === 'resigned' ? `${s.reason} · ${s.winner === 'w' ? 'White' : 'Black'} wins`
      : `Draw · ${s.reason}`
  } else if (s.thinking) { status = 'Bot is thinking…'; tone = 'think' }
  else if (s.check) { status = (bot ? (s.turn === human ? 'Your king is in check!' : 'Check!') : `${s.turn === 'w' ? 'White' : 'Black'} is in check!`); tone = 'check' }
  else if (bot) status = s.turn === human ? 'Your move' : '…'
  else status = `${s.turn === 'w' ? 'White' : 'Black'} to move`

  const pairs: { n: number; w: string; b?: string }[] = []
  for (let i = 0; i < s.history.length; i += 2) pairs.push({ n: i / 2 + 1, w: s.history[i], b: s.history[i + 1] })

  const doConfirm = () => {
    if (confirm === 'resign') game.resign()
    if (confirm === 'draw') game.agreeDraw()
    if (confirm === 'new') game.start(s.config)
    setConfirm(null)
  }
  const over = s.status !== 'playing'

  return (
    <aside className="side">
      <div className="side-top">
        <div className="topbar">
          <button className="icon-btn" onClick={onMenu} aria-label="Menu">☰</button>
          <div className={`status ${tone}`} role="status" aria-live="polite">{status}</div>
          <button className="icon-btn" onClick={onSettings} aria-label="Settings">⚙</button>
        </div>
        <PlayerCard s={s} color={opp} label={bot ? `Bot · ${s.config.elo}` : opp === 'b' ? 'Black' : 'White'} sub={bot ? (opp === 'w' ? 'White' : 'Black') : undefined} />
        <div className="moves" ref={movesRef} aria-label="Move list">
          {pairs.length === 0 && <span className="muted">Moves appear here</span>}
          {pairs.map((p) => (
            <span className="mv" key={p.n}><i>{p.n}.</i> {p.w} {p.b ?? ''}</span>
          ))}
        </div>
      </div>
      <div className="side-bottom">
        <PlayerCard s={s} color={me} label={bot ? 'You' : me === 'w' ? 'White' : 'Black'} sub={bot ? (me === 'w' ? 'White' : 'Black') : undefined} />
        <div className="controls">
          <button disabled={!s.canUndo} onClick={() => game.undo()} title="Undo"><b>↶</b><span>Undo</span></button>
          <button onClick={() => game.board.flipView()} title="Flip view"><b>⟳</b><span>Flip</span></button>
          <button className={topView ? 'on' : ''} onClick={() => { const next = !topView; setTopView(next); game.board.resetCamera(true, game.board.viewSide(), next) }} title="Top-down view"><b>⬒</b><span>Top</span></button>
          <button onClick={() => { setTopView(false); game.board.resetCamera(true, bot ? human : game.board.viewSide()) }} title="Reset camera"><b>◎</b><span>Reset</span></button>
          {over
            ? <button onClick={() => setConfirm('new')} title="Rematch"><b>♻</b><span>Rematch</span></button>
            : bot
              ? <button onClick={() => setConfirm('resign')} title="Resign"><b>⚑</b><span>Resign</span></button>
              : <>
                  <button onClick={() => setConfirm('draw')} title="Agree a draw"><b>½</b><span>Draw</span></button>
                  <button onClick={() => setConfirm('resign')} title="Resign"><b>⚑</b><span>Resign</span></button>
                </>}
        </div>
      </div>
      {confirm && (
        <div className="modal-bg" onClick={() => setConfirm(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} role="alertdialog">
            <h3>{confirm === 'resign' ? `${bot || s.turn === 'w' ? (bot ? 'Resign' : 'White resigns') : 'Black resigns'}?` : confirm === 'draw' ? 'Both players agree to a draw?' : 'Start a rematch?'}</h3>
            <div className="row">
              <button className="secondary" onClick={() => setConfirm(null)}>Cancel</button>
              <button className="primary" onClick={doConfirm}>Yes</button>
            </div>
          </div>
        </div>
      )}
    </aside>
  )
}
