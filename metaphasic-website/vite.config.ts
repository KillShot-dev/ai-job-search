import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Static export suitable for IONOS (upload dist/ to web root)
export default defineConfig({
  plugins: [react()],
  // Domain-root deploy on IONOS (metaphasic.net). Required for BrowserRouter + /products.
  base: '/',
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
  },
})
