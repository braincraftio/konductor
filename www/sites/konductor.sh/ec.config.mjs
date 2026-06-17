// @ts-check
import { defineEcConfig } from 'astro-expressive-code'

export default defineEcConfig({
  // Use built-in themes — rename to 'dark'/'light' so themeCssSelector
  // generates [data-theme="dark"] and [data-theme="light"], matching
  // Aurora's existing theme switching mechanism.
  themes: ['github-dark', 'github-light'],
  customizeTheme: (theme) => {
    if (theme.type === 'dark') {
      theme.name = 'dark'
    } else {
      theme.name = 'light'
    }
  },

  // Aurora design system integration via CSS custom properties.
  // Expressive Code owns syntax highlighting colors (from the themes above).
  // Chrome (borders, backgrounds, radius, fonts) references Aurora tokens
  // so code blocks stay visually consistent with the rest of the site.
  styleOverrides: {
    borderColor: 'var(--code-border)',
    borderRadius: '0.75rem',
    borderWidth: '1px',
    codeBackground: 'var(--code-bg)',
    codeFontFamily: "'Space Mono', monospace",
    codeFontSize: '0.875rem',
    codeLineHeight: '1.7',
    codePaddingBlock: '1rem',
    codePaddingInline: '1rem',
    focusBorder: 'var(--focus)',
    uiFontFamily: "'Inter', system-ui, sans-serif",
    uiFontSize: '0.8rem',
    frames: {
      editorTabBarBackground: 'var(--surface-subtle)',
      editorActiveTabBackground: 'var(--code-bg)',
      editorActiveTabForeground: 'var(--text-primary)',
      terminalBackground: 'var(--code-bg)',
      terminalTitlebarBackground: 'var(--surface-subtle)',
      terminalTitlebarForeground: 'var(--text-tertiary)',
      terminalTitlebarBorderBottomColor: 'var(--code-border)',
      shadowColor: 'transparent',
    },
  },

  // themeCssSelector defaults to (theme) => `[data-theme='${theme.name}']`
  // which matches our renamed themes exactly — no override needed.

  // useDarkModeMediaQuery defaults to true when one dark + one light theme
  // are provided, giving us automatic prefers-color-scheme support.
})
