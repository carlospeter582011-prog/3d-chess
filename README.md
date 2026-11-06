# 3D Chess (PWA)

Play chess on a 3D Staunton set (your own GLB models) in the browser or installed on a phone.

- **2 players on one device** (pass & play) or **vs a Stockfish bot** with a chosen Elo (400–3200, approximate)
- Full rules via [chess.js](https://github.com/jhlywa/chess.js): castling, en passant, promotion, check/checkmate, stalemate, threefold repetition, fifty-move rule, insufficient material
- Orbit / tilt (drag), pan (two fingers or right-drag), zoom (pinch or wheel); never goes below the table
- **Offline**: the 3D models are downloaded once into Cache Storage, the app shell + Stockfish are precached by the service worker
- Installable (Add to Home Screen / Install app); logo rendered from the knight model

## Develop
```bash
npm install
npm run dev        # http://localhost:5173
npm run build      # production build in dist/ (relative base: works on a domain root or a sub-path)
npm run preview
```

## Models
`public/models/*.glb` are optimised versions of the supplied pieces (rescaled to real Staunton proportions, base on y = 0,
centred on the square, 12–24k triangles, WebP textures; 49 MB → ~10 MB). Regenerate from the originals with
`node tools/optimize-models.mjs public/models ./raw-models/` (needs `@gltf-transform/*`, `meshoptimizer`, `sharp`).
Board space: 1 square = 1 unit, a1 at (-3.5, y, +3.5), white on +z.

## Deploy
Push to `main`; the included GitHub Actions workflow publishes to GitHub Pages (Settings → Pages → Source: GitHub Actions).
Any static host works too (Vercel/Netlify: build `npm run build`, output `dist`). HTTPS is required for install + offline.
