// Aurora Design System — raw palette constants.
// Single source of truth consumed by:
//   - Layout.astro: inline <style> anti-flash (SSG build-time interpolation)
//   - global.css: CSS custom properties (referenced via oklch literals)
//
// When adding themes, add entries to the themes map. Layout.astro generates
// anti-flash CSS for each theme automatically at build time.

export const palette = {
  cream: {
    50: 'oklch(98% 0.01 85)',
    100: 'oklch(97% 0.015 85)',
    200: 'oklch(95% 0.02 85)',
    300: 'oklch(92% 0.025 85)',
    400: 'oklch(88% 0.03 85)',
  },
  slate: {
    50: 'oklch(98% 0.015 295)',
    100: 'oklch(96% 0.020 295)',
    200: 'oklch(92% 0.028 295)',
    300: 'oklch(84% 0.035 295)',
    400: 'oklch(71% 0.045 295)',
    500: 'oklch(55% 0.055 295)',
    600: 'oklch(43% 0.065 295)',
    700: 'oklch(33% 0.075 295)',
    800: 'oklch(25% 0.080 295)',
    900: 'oklch(18% 0.085 295)',
  },
} as const;

// Theme definitions: surface background + text foreground for anti-flash.
// Each theme's values must match what global.css resolves for that theme's
// --surface-base and --text-primary after the full token chain evaluates.
export const themes = {
  dark: {
    background: palette.slate[900],
    foreground: palette.cream[100],
  },
  light: {
    background: palette.cream[100],
    foreground: palette.slate[800],
  },
} as const;

export type ThemeName = keyof typeof themes;
