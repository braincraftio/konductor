import { defineConfig } from 'astro/config';
import expressiveCode from 'astro-expressive-code';
import mdx from '@astrojs/mdx';
import pagefind from 'astro-pagefind';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://braincraftio.github.io',
  base: '/konductor',
  // expressiveCode() MUST come before mdx() — it needs to process
  // fenced code blocks before MDX compilation.
  integrations: [expressiveCode(), mdx(), pagefind()],
  vite: {
    plugins: [tailwindcss()],
    server: {
      fs: {
        // Allow reading src/lib/versions.nix from the repo root for
        // the specs page raw nix display. Eliminates the stale copy
        // in src/data/versions.nix.
        allow: ['../../../../../src/lib']
      }
    }
  }
});
