import React, { useState, useEffect } from 'react';

const navLinks = [
  { name: 'About', href: '/about' },
  { name: 'Specs', href: '/specs' },
  { name: 'Manual', href: '/manual' },
];

const ecosystemLinks = [
  { name: 'BrainCraft', href: 'https://braincraft.io', external: true },
];

export default function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [theme, setTheme] = useState<'light' | 'dark'>('light');

  useEffect(() => {
    // Scroll handler
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);

    // Theme handler
    const storedTheme = localStorage.getItem('aurora-theme');
    // Default to 'light' if no stored preference, ignoring system preference
    const initialTheme = (storedTheme as 'light' | 'dark') || 'light';
    
    setTheme(initialTheme);
    document.documentElement.setAttribute('data-theme', initialTheme);

    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const toggleTheme = () => {
    const newTheme = theme === 'light' ? 'dark' : 'light';
    setTheme(newTheme);
    localStorage.setItem('aurora-theme', newTheme);
    document.documentElement.setAttribute('data-theme', newTheme);
  };

  return (
    <header  
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 border-b ${
        isScrolled 
          ? 'bg-surface-paper/90 backdrop-blur-md border-border-subtle py-3 shadow-sm' 
          : 'bg-transparent border-transparent py-5'
      }`}
    >
      <div className="max-w-7xl mx-auto px-6 flex items-center justify-between">
        {/* Logo / Home */}
        <a href="/" className="group flex items-center gap-3 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-primary rounded-lg p-1">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-brand-primary to-brand-secondary flex items-center justify-center text-slate-800 font-mono font-bold text-lg shadow-lg group-hover:scale-105 transition-transform duration-300">
            K
          </div>
          <span className="font-bold text-lg tracking-tight text-text-primary group-hover:text-brand-primary transition-colors">
            Konductor<span className="text-text-tertiary">.sh</span>
          </span>
        </a>

        {/* Desktop Nav */}
        <nav className="hidden md:flex items-center gap-8">
          <div className="flex items-center gap-6 border-r border-border-subtle pr-6 mr-2">
            {navLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                className="text-sm font-medium text-text-secondary hover:text-brand-primary transition-colors hover:-translate-y-0.5 transform duration-200"
              >
                {link.name}
              </a>
            ))}
          </div>
          
          <div className="flex items-center gap-4">
             {ecosystemLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs font-medium text-text-tertiary hover:text-text-primary transition-colors uppercase tracking-wider"
              >
                {link.name}
              </a>
            ))}
            
            <button
                onClick={toggleTheme}
                className="p-2 ml-2 rounded-full text-text-secondary hover:text-brand-primary hover:bg-surface-subtle transition-all duration-200"
                aria-label="Toggle theme"
            >
                {theme === 'light' ? (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
                    </svg>
                ) : (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
                    </svg>
                )}
            </button>
          </div>
        </nav>

        {/* Mobile Menu Toggle */}
        <button 
          onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
          className="md:hidden p-2 text-text-secondary hover:text-text-primary focus:outline-none focus:ring-2 focus:ring-brand-primary rounded-md"
          aria-label="Toggle menu"
        >
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            {isMobileMenuOpen ? (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>

        {/* Mobile Menu */}
      {isMobileMenuOpen && (
        <div className="md:hidden absolute top-full left-0 right-0 bg-surface-paper border-b border-border-subtle shadow-xl p-6 space-y-6 animate-in slide-in-from-top-2 duration-200">
          <div className="flex flex-col gap-4">
            {navLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                className="text-base font-medium text-text-primary hover:text-brand-primary py-2 border-b border-border-subtle/50"
                onClick={() => setIsMobileMenuOpen(false)}
              >
                {link.name}
              </a>
            ))}
          </div>
          <div className="flex flex-col gap-3 pt-2">
            <span className="text-xs font-bold text-text-tertiary uppercase tracking-widest">Ecosystem</span>
            {ecosystemLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                className="text-sm font-medium text-text-secondary hover:text-text-primary"
              >
                {link.name}
              </a>
            ))}
          </div>
        </div>
      )}
    </header>
  );
}
