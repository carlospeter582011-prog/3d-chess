import { useEffect, useState } from 'react'
import type { Color } from '../three/Board3D'
import type { GameConfig, Settings } from '../chess/Game'
import { ELO_MAX, ELO_MIN } from '../chess/engine'
import { eloName } from './glyphs'

interface Props {
  settings: Settings
  onSettings: (s: Settings) => void
  saved: { config: GameConfig; pgn: string } | null
  hasActive: boolean
  offlineReady: boolean
  onStart: (cfg: GameConfig) => void
  onContinue: () => void
  onResumeSaved: () => void
  onOpenSettings: () => void
}

interface InstallEvent extends Event { prompt: () => Promise<void>; userChoice: Promise<{ outcome: string }> }

const PRESETS = [400, 800, 1200, 1600, 2000, 2400, 2800, 3200]

export function Menu(p: Props) {
  const { settings, onSettings } = p
  const [install, setInstall] = useState<InstallEvent | null>(null)
  const [installed, setInstalled] = useState(false)
  useEffect(() => {
    const h = (e: Event) => { e.preventDefault(); setInstall(e as InstallEvent) }
    const d = () => setInstalled(true)
    window.addEventListener('beforeinstallprompt', h)
    window.addEventListener('appinstalled', d)
    return () => { window.removeEventListener('beforeinstallprompt', h); window.removeEventListener('appinstalled', d) }
  }, [])
  const standalone = window.matchMedia('(display-mode: standalone)').matches || (navigator as unknown as { standalone?: boolean }).standalone
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent) && !standalone

  const set = (patch: Partial<Settings>) => onSettings({ ...settings, ...patch })
  const bot = settings.mode === 'bot'

  const start = () => {
    const human: Color = settings.humanColor === 'r' ? (Math.random() < 0.5 ? 'w' : 'b') : settings.humanColor
    p.onStart({ mode: settings.mode, humanColor: human, elo: settings.elo })
  }

  return (
    <div className="menu" role="dialog" aria-label="Main menu">
      <div className="menu-card">
        <header className="brand">
          <img src={`${import.meta.env.BASE_URL}icons/icon-192.png`} alt="" width={64} height={64} />
          <div>
            <h1>3D Chess</h1>
            <p>Staunton set · works offline</p>
          </div>
          <button className="icon-btn" onClick={p.onOpenSettings} aria-label="Settings">⚙</button>
        </header>

        <div className="seg" role="tablist">
          <button role="tab" aria-selected={bot} className={bot ? 'on' : ''} onClick={() => set({ mode: 'bot' })}>🤖 Play the bot</button>
          <button role="tab" aria-selected={!bot} className={!bot ? 'on' : ''} onClick={() => set({ mode: 'local' })}>👥 2 players · 1 device</button>
        </div>

        {bot ? (
          <>
            <section>
              <h2>Your colour</h2>
              <div className="seg small">
                {([['w', '♔ White'], ['r', '🎲 Random'], ['b', '♚ Black']] as const).map(([v, label]) => (
                  <button key={v} className={settings.humanColor === v ? 'on' : ''} onClick={() => set({ humanColor: v })}>{label}</button>
                ))}
              </div>
            </section>
            <section>
              <h2>Bot strength <span className="elo-val">{settings.elo} Elo</span> <span className="elo-name">{eloName(settings.elo)}</span></h2>
              <input className="range" type="range" min={ELO_MIN} max={ELO_MAX} step={50} value={settings.elo}
                aria-label="Bot Elo" onChange={(e) => set({ elo: +e.target.value })} />
              <div className="chips">
                {PRESETS.map((e) => <button key={e} className={Math.abs(settings.elo - e) < 25 ? 'chip on' : 'chip'} onClick={() => set({ elo: e })}>{e}</button>)}
              </div>
              <p className="hint">Stockfish runs on your device. Elo is approximate.</p>
            </section>
          </>
        ) : (
          <section>
            <p className="hint big">Pass the phone or tablet back and forth — no internet needed. Turn on “Auto-turn view” in settings to spin the board to the player whose turn it is.</p>
          </section>
        )}

        <button className="primary" onClick={start}>▶ Start new game</button>
        {p.hasActive === false && p.saved && (
          <button className="secondary" onClick={p.onResumeSaved}>
            ↺ Continue saved game ({p.saved.config.mode === 'bot' ? `bot ${p.saved.config.elo}` : '2 players'})
          </button>
        )}
        {p.hasActive && <button className="secondary" onClick={p.onContinue}>↺ Back to current game</button>}

        <footer className="menu-foot">
          <span className={p.offlineReady ? 'badge ok' : 'badge'}>{p.offlineReady ? '✓ Offline ready' : '… caching for offline'}</span>
          {!standalone && !installed && install && (
            <button className="install" onClick={async () => { await install.prompt(); setInstall(null) }}>⬇ Install app</button>
          )}
          {ios && <span className="hint">iPhone: Share → “Add to Home Screen”</span>}
        </footer>
      </div>
    </div>
  )
}
