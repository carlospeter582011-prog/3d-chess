// Tiny synthesized wood-click sounds (no audio files -> nothing to download or cache).
let ctx: AudioContext | null = null
let muted = false
export function setMuted(m: boolean) { muted = m }

function ac(): AudioContext | null {
  if (muted) return null
  try {
    const C = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    ctx = ctx ?? new C()
    if (ctx.state === 'suspended') void ctx.resume()
    return ctx
  } catch { return null }
}

function click(freq: number, dur: number, gain: number, noise = 0.5) {
  const a = ac(); if (!a) return
  const t = a.currentTime
  const len = Math.floor(a.sampleRate * dur)
  const buf = a.createBuffer(1, len, a.sampleRate)
  const d = buf.getChannelData(0)
  for (let i = 0; i < len; i++) {
    const env = Math.exp(-i / (len * 0.18))
    d[i] = ((Math.random() * 2 - 1) * noise + Math.sin((2 * Math.PI * freq * i) / a.sampleRate) * (1 - noise)) * env
  }
  const src = a.createBufferSource(); src.buffer = buf
  const bp = a.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = freq * 1.6; bp.Q.value = 0.9
  const g = a.createGain(); g.gain.value = gain
  src.connect(bp).connect(g).connect(a.destination)
  src.start(t)
}

export const sfx = {
  move: () => click(260, 0.12, 0.9),
  capture: () => { click(190, 0.16, 1.2, 0.7); setTimeout(() => click(320, 0.08, 0.6), 40) },
  check: () => { click(520, 0.18, 0.7, 0.2); setTimeout(() => click(690, 0.22, 0.6, 0.1), 110) },
  end: () => { click(330, 0.3, 0.7, 0.1); setTimeout(() => click(247, 0.4, 0.7, 0.1), 180) },
}
