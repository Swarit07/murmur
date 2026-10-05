import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Relative base so the build works from any path (GitHub Pages, a subfolder, or a root domain).
export default defineConfig({
  plugins: [react()],
  base: './',
});
