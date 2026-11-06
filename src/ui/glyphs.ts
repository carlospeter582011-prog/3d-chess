import type { PType } from '../three/Board3D'
export const GLYPH: Record<PType, string> = { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' }
export const VALUE: Record<PType, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 }
export function eloName(e: number): string {
  if (e < 600) return 'Beginner'
  if (e < 1000) return 'Novice'
  if (e < 1400) return 'Casual'
  if (e < 1800) return 'Club player'
  if (e < 2200) return 'Advanced'
  if (e < 2600) return 'Expert'
  if (e < 3000) return 'Master'
  return 'Grandmaster+'
}
