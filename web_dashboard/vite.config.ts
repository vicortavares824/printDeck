import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// SPA React + Vite isolada. Não compartilha build/deps com o app Flutter nem com cloud_api.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
});
