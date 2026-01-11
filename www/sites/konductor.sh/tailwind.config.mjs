/** @type {import('tailwindcss').Config} */
export default {
	content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
	theme: {
		extend: {
			colors: {
				// We will rely heavily on CSS variables defined in global.css
				// referencing the Aurora system's semantic tokens
				cream: {
					50: 'var(--cream-50)',
					100: 'var(--cream-100)',
					200: 'var(--cream-200)',
					300: 'var(--cream-300)',
					400: 'var(--cream-400)',
				},
				slate: {
					50: 'var(--slate-50)',
					100: 'var(--slate-100)',
					200: 'var(--slate-200)',
					300: 'var(--slate-300)',
					400: 'var(--slate-400)',
					500: 'var(--slate-500)',
					600: 'var(--slate-600)',
					700: 'var(--slate-700)',
					800: 'var(--slate-800)',
					900: 'var(--slate-900)',
				},
				lavender: {
					300: 'var(--lavender-300)',
					400: 'var(--lavender-400)',
					500: 'var(--lavender-500)',
				},
				mint: {
					300: 'var(--mint-300)',
					400: 'var(--mint-400)',
					500: 'var(--mint-500)',
				},
				peach: {
					300: 'var(--peach-300)',
					400: 'var(--peach-400)',
					500: 'var(--peach-500)',
				},
				sky: {
					300: 'var(--sky-300)',
					400: 'var(--sky-400)',
					500: 'var(--sky-500)',
				},
				// Semantic mappings
				surface: {
					base: 'var(--color-surface-base)',
					paper: 'var(--color-surface-paper)',
					raised: 'var(--color-surface-raised)',
					subtle: 'var(--color-surface-subtle)',
				},
				text: {
					primary: 'var(--color-text-primary)',
					secondary: 'var(--color-text-secondary)',
					tertiary: 'var(--color-text-tertiary)',
					disabled: 'var(--color-text-disabled)',
					inverse: 'var(--color-text-inverse)',
				},
				border: {
					subtle: 'var(--color-border-subtle)',
					DEFAULT: 'var(--color-border-default)',
					strong: 'var(--color-border-strong)',
				},
				brand: {
					primary: 'var(--color-primary)',
					secondary: 'var(--color-secondary)',
					accent: 'var(--color-accent)',
				},
				focus: {
					DEFAULT: 'var(--color-focus)',
					ring: 'var(--color-focus-ring)',
				}
			},
			fontFamily: {
				sans: ['Inter', 'system-ui', 'sans-serif'],
				mono: ['Space Mono', 'monospace'],
			},
			fontSize: {
				xs: 'var(--text-xs)',
				sm: 'var(--text-sm)',
				base: 'var(--text-base)',
				lg: 'var(--text-lg)',
				xl: 'var(--text-xl)',
				'2xl': 'var(--text-2xl)',
				'3xl': 'var(--text-3xl)',
				'4xl': 'var(--text-4xl)',
				'5xl': 'var(--text-5xl)',
			},
			spacing: {
				px: 'var(--space-px)',
				0.5: 'var(--space-0_5)',
				1: 'var(--space-1)',
				1.5: 'var(--space-1_5)',
				2: 'var(--space-2)',
				2.5: 'var(--space-2_5)',
				3: 'var(--space-3)',
				3.5: 'var(--space-3_5)',
				4: 'var(--space-4)',
				5: 'var(--space-5)',
				6: 'var(--space-6)',
				7: 'var(--space-7)',
				8: 'var(--space-8)',
				9: 'var(--space-9)',
				10: 'var(--space-10)',
				12: 'var(--space-12)',
				16: 'var(--space-16)',
				20: 'var(--space-20)',
				24: 'var(--space-24)',
				32: 'var(--space-32)',
			},
			borderRadius: {
				sm: 'var(--radius-sm)',
				md: 'var(--radius-md)',
				lg: 'var(--radius-lg)',
				xl: 'var(--radius-xl)',
				'2xl': 'var(--radius-2xl)',
				'3xl': 'var(--radius-3xl)',
			},
			boxShadow: {
				xs: 'var(--shadow-xs)',
				sm: 'var(--shadow-sm)',
				md: 'var(--shadow-md)',
				lg: 'var(--shadow-lg)',
				xl: 'var(--shadow-xl)',
				lavender: 'var(--shadow-lavender)',
				mint: 'var(--shadow-mint)',
				peach: 'var(--shadow-peach)',
			},
			transitionDuration: {
				instant: 'var(--duration-instant)',
				fast: 'var(--duration-fast)',
				normal: 'var(--duration-normal)',
				slow: 'var(--duration-slow)',
				slower: 'var(--duration-slower)',
			},
			transitionTimingFunction: {
				spring: 'var(--ease-spring)',
				'spring-smooth': 'var(--ease-spring-smooth)',
				bounce: 'var(--ease-bounce)',
			}
		},
	},
	plugins: [
		require('@tailwindcss/typography'),
	],
};
