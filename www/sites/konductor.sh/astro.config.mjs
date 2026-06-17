import { defineConfig } from 'astro/config';
import expressiveCode from 'astro-expressive-code';
import mdx from '@astrojs/mdx';
import pagefind from 'astro-pagefind';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://konductor.sh',
  // expressiveCode() MUST come before mdx() — it needs to process
  // fenced code blocks before MDX compilation.
  integrations: [expressiveCode(), mdx(), pagefind()],
  vite: {
    plugins: [tailwindcss()]
  }
});
