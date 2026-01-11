import React from 'react';

export default function CodeBlock({ children, className = '' }: { children: React.ReactNode, className?: string }) {
  return (
    <div className={`relative group code-block-wrapper ${className}`}>
      <button
        className="copy-code-button absolute top-3 right-3 p-2 rounded-lg bg-slate-800/50 text-slate-400 hover:text-white hover:bg-slate-700 border border-slate-700/50 backdrop-blur-sm transition-all opacity-0 group-hover:opacity-100 focus:opacity-100 z-10"
        aria-label="Copy code"
      >
        <span className="copy-icon">
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3" />
          </svg>
        </span>
        <span className="check-icon hidden">
          <svg className="w-4 h-4 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </span>
      </button>
      {children}
    </div>
  );
}
