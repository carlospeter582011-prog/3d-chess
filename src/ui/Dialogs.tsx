import type { Game, GameSnapshot, Settings } from '../chess/Game'
import type { Color } from '../three/Board3D'
import { GLYPH } from './glyphs'

export function PromotionDialog({ game, color }: { game: Game; color: Color }) {
  const opts = ['q', 'r', 'b', 'n'] as const
  const names = { q: 'Queen', r: 'Rook', b: 'Bishop', n: 'Knight' }
  return (
    <div className="modal-bg" onClick={() => game.cancelPromotion()}>
      <div className="modal promo" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="Choose promotion piece">
        <h3>Promote pawn to…</h3>
        <div className="promo-row">
          {opts.map((o) => (
            <button key={o} data-promo={o} onClick={() => game.choosePromotion(o)} aria-label={names[o]}>
              <span className={`pg ${color === 'w' ? 'cw' : 'cb'}`}>{GLYPH[o]}</span>
              <small>{names[o]}</small>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

export function ResultDialog({ s, onRematch, onMenu, onClose }: { s: GameSnapshot; onRematch: () => void; onMenu: () => void; onClose: () => void }) {
  const bot = s.config.mode === 'bot'
  let title = 'Draw'
  if (s.winner) title = bot ? (s.winner === s.config.humanColor ? 'You win! 🎉' : 'Bot wins') : `${s.winner === 'w' ? 'White' : 'Black'} wins!`
  return (
    <div className="modal-bg">
      <div className="modal result" role="dialog" aria-label="Game over">
        <h2>{title}</h2>
        <p>{s.reason}{s.history.length ? ` · ${Math.ceil(s.history.length / 2)} moves` : ''}</p>
        <div className="row">
          <button className="secondary" onClick={onClose}>View board</button>
          <button className="secondary" onClick={onMenu}>Menu</button>
          <button className="primary" onClick={onRematch}>Rematch</button>
        </div>
      </div>
    </div>
  )
}

export function SettingsDialog({ settings, onChange, onClose }: { settings: Settings; onChange: (s: Settings) => void; onClose: () => void }) {
  const Toggle = ({ k, label, hint }: { k: 'sound' | 'labels' | 'autoFlip'; label: string; hint?: string }) => (
    <label className="toggle">
      <span><b>{label}</b>{hint && <small>{hint}</small>}</span>
      <input type="checkbox" checked={settings[k]} onChange={(e) => onChange({ ...settings, [k]: e.target.checked })} />
      <i />
    </label>
  )
  return (
    <div className="modal-bg" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-label="Settings">
        <h3>Settings</h3>
        <Toggle k="sound" label="Sound effects" />
        <Toggle k="labels" label="Board coordinates" hint="a–h and 1–8 around the board" />
        <Toggle k="autoFlip" label="Auto-turn view (2 players)" hint="Rotates the camera to whoever moves next" />
        <label className="toggle">
          <span><b>Graphics</b><small>Low turns off shadows (faster on old phones)</small></span>
          <select value={settings.quality} onChange={(e) => onChange({ ...settings, quality: e.target.value as 'high' | 'low' })}>
            <option value="high">High</option><option value="low">Low</option>
          </select>
        </label>
        <p className="hint">Drag to orbit · two fingers to pan and zoom · right-drag / scroll on desktop.</p>
        <div className="row"><button className="primary" onClick={onClose}>Done</button></div>
      </div>
    </div>
  )
}
