import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Static export suitable for IONOS (upload dist/ to web root)
export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
  },
})
