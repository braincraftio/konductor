// Centralized path helper for base URL support.
// All internal links should use url() to respect the base path
// configured in astro.config.mjs (e.g., '/konductor' for GitHub Pages).
//
// Usage in .astro files:
//   import { href } from '../utils/paths';
//   <a href={href('/manual')}>Manual</a>
//
// When base is '/', href('/manual') returns '/manual'.
// When base is '/konductor', href('/manual') returns '/konductor/manual'.

const base = import.meta.env.BASE_URL.replace(/\/$/, '');

export function href(path: string): string {
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}
