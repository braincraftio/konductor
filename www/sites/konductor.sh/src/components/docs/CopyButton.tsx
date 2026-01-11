import React, { useState } from 'react';

export default function CopyButton({ text, label = 'Copy', className = '' }: { text?: string, label?: string, className?: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    // If text is provided, copy it directly
    if (text) {
      navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
      return;
    }

    // Otherwise, try to copy the page content as markdown
    // This is a simplified markdown conversion for the current page article
    const article = document.querySelector('article');
    if (article) {
      // Basic HTML to Markdown (simplified)
      let markdown = article.innerText;
      navigator.clipboard.writeText(markdown);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <button
      onClick={handleCopy}
      className={`inline-flex items-center gap-2 px-3 py-1.5 text-xs font-medium rounded-md transition-all duration-300 ${
        copied 
          ? 'bg-success-bg text-success-base border border-success-border shadow-sm' 
          : 'bg-surface-paper text-text-secondary hover:text-text-primary border border-border-default hover:border-border-strong shadow-sm hover:shadow-md hover:-translate-y-0.5'
      } ${className}`}
    >
      {copied ? (
        <>
          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
          <span>Copied!</span>
        </>
      ) : (
        <>
          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3" />
          </svg>
          <span>{label}</span>
        </>
      )}
    </button>
  );
}
