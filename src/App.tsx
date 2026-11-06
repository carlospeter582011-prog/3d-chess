import { useEffect, useRef, useState, useSyncExternalStore, useCallback } from 'react'
import { Board3D } from './three/Board3D'
import { Game, loadSettings, saveSettings } from './chess/Game'
import type { GameConfig, Settings } from './chess/Game'
import { isFullyCached, requestPersistentStorage } from './three/modelCache'
import { Menu } from './ui/Menu'
import { Hud } from './ui/Hud'
import { PromotionDialog, ResultDialog, SettingsDialog } from './ui/Dialogs'

declare global { interface Window { __chess?: { game: Game; board: Board3D } } }

export default function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [game, setGame] = useState<Game | null>(null)
  const [progress, setProgress] = useState<[number, number]>([0, 13])
  const [error, setError] = useState<string | null>(null)
  const [attempt, setAttempt] = useState(0)
  const [settings, setSettings] = useState<Settings>(loadSettings)
  const [showSettings, setShowSettings] = useState(false)
  const [offlineReady, setOfflineReady] = useState(false)
  const [showResult, setShowResult] = useState(false)
  const [saved, setSaved] = useState(Game.loadSaved)
  const gameRef = useRef<Game | null>(null)
  const settingsRef = useRef(settings)
  settingsRef.current = settings

  useEffect(() => {
    const canvas = canvasRef.current!
    let board: Board3D | null = null
    let cancelled = false
    setError(null)
    try {
      board = new Board3D({ canvas, quality: settingsRef.current.quality, onTap: (sq, ground) => gameRef.current?.tap(sq, ground) })
    } catch (e) {
      setError('Your browser could not start WebGL (3D graphics). ' + (e as Error).message)
      return
    }
    board.load((d, t) => !cancelled && setProgress([d, t])).then(async () => {
      if (cancelled || !board) return
      const g = new Game(board)
      g.setSettings(settingsRef.current)
      g.syncBoard()
      board.controls.autoRotate = true
      board.controls.autoRotateSpeed = 0.7
      gameRef.current = g
      window.__chess = { game: g, board }
      setGame(g)
      void requestPersistentStorage()
      for (let i = 0; i < 12 && !cancelled; i++) {
        if (await isFullyCached()) { setOfflineReady(true); break }
        await new Promise((r) => setTimeout(r, 1500))
      }
    }).catch((e) => { console.error('[chess3d] startup error', e); if (!cancelled) setError('Could not load the 3D models. ' + (e as Error).message) })
    return () => { cancelled = true; board?.dispose(); gameRef.current = null }
  }, [attempt])

  const snap = useSyncExternalStore(
    game ? game.subscribe : (() => () => {}),
    game ? game.getSnapshot : (() => null),
  )

  const updateSettings = useCallback((s: Settings) => {
    setSettings(s)
    saveSettings(s)
    const g = gameRef.current
    if (g) { g.setSettings(s); g.board.setQuality(s.quality) }
  }, [])

  // show the result card when a game ends
  const status = snap?.status
  useEffect(() => { setShowResult(!!status && status !== 'playing' && !!snap?.active) }, [status, snap?.active])
  // attract-mode rotation only while the menu is up
  useEffect(() => { if (game) { game.board.controls.autoRotate = !snap?.active; game.board.requestRender() } }, [game, snap?.active])

  const start = (cfg: GameConfig) => { Game.clearSaved(); game?.start(cfg); setSaved(null) }
  const resumeSaved = () => { if (!game || !saved) return; game.start(saved.config, { pgn: saved.pgn }) }
  const active = !!snap?.active
  const loading = !game

  return (
    <div className={`app ${active ? 'with-side' : ''}`}>
      <div className="stage"><canvas ref={canvasRef} aria-label="3D chess board" /></div>

      {loading && (
        <div className="loading">
          <img src={`${import.meta.env.BASE_URL}icons/icon-192.png`} width={96} height={96} alt="" />
          <h1>3D Chess</h1>
          {error ? (
            <>
              <p className="err">{error}</p>
              <button className="primary" onClick={() => { setProgress([0, 13]); setAttempt((a) => a + 1) }}>Try again</button>
            </>
          ) : (
            <>
              <div className="bar"><div style={{ width: `${(progress[0] / progress[1]) * 100}%` }} /></div>
              <p>Loading 3D pieces… {progress[0]}/{progress[1]}</p>
              <small>First launch downloads the models (~10 MB) and saves them for offline play.</small>
            </>
          )}
        </div>
      )}

      {game && snap && !active && (
        <Menu settings={settings} onSettings={updateSettings} saved={saved}
          hasActive={snap.history.length > 0 && snap.status === 'playing'} offlineReady={offlineReady}
          onStart={start} onContinue={() => game.resume()} onResumeSaved={resumeSaved}
          onOpenSettings={() => setShowSettings(true)} />
      )}
      {game && snap && active && (
        <Hud game={game} s={snap} onMenu={() => game.leave()} onSettings={() => setShowSettings(true)} />
      )}
      {game && snap?.promotion && active && <PromotionDialog game={game} color={snap.turn} />}
      {game && snap && active && showResult && (
        <ResultDialog s={snap} onClose={() => setShowResult(false)} onMenu={() => { setShowResult(false); game.leave() }} onRematch={() => { setShowResult(false); game.start(snap.config) }} />
      )}
      {showSettings && <SettingsDialog settings={settings} onChange={updateSettings} onClose={() => setShowSettings(false)} />}
    </div>
  )
}
