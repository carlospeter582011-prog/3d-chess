import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

// Relative base so the same build works on a domain root (Vercel/Netlify) or a sub-path (GitHub Pages).
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: ['icons/*.png', 'engine/*'],
      manifest: {
        name: '3D Chess',
        short_name: '3D Chess',
        description: '3D chess with a real Staunton set. Play a friend or a Stockfish bot at any Elo, fully offline.',
        theme_color: '#14100d',
        background_color: '#14100d',
        display: 'standalone',
        orientation: 'any',
        start_url: './',
        scope: './',
        categories: ['games'],
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // App shell + the Stockfish engine are precached. The 3D models are cached by the app itself
        // (with a progress bar) into the same Cache Storage and served cache-first here.
        globPatterns: ['**/*.{js,css,html,png,svg,wasm,webmanifest}'],
        globIgnores: ['models/**'],
        maximumFileSizeToCacheInBytes: 8 * 1024 * 1024,
        navigateFallback: 'index.html',
        cleanupOutdatedCaches: true,
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.pathname.includes('/models/') && url.pathname.endsWith('.glb'),
            handler: 'CacheFirst',
            options: { cacheName: 'chess3d-models-v1', cacheableResponse: { statuses: [0, 200] } },
          },
        ],
      },
    }),
  ],
  build: { chunkSizeWarningLimit: 1200 },
})
