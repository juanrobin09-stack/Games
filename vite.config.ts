import { defineConfig } from 'vite';
import path from 'node:path';

export default defineConfig({
  base: './',
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, 'src'),
    },
  },
  build: {
    target: 'es2020',
    sourcemap: false,
    chunkSizeWarningLimit: 1000,
  },
  server: {
    host: true,
    port: 5173,
  },
});
