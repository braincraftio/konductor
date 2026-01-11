import React, { useState, useMemo } from 'react';

interface DocEntry {
  slug: string;
  data: {
    title: string;
    section: string;
    order: number;
  };
}

interface SidebarProps {
  sections: string[];
  groupedDocs: Record<string, DocEntry[]>;
  currentSlug: string;
}

export default function Sidebar({ sections, groupedDocs, currentSlug }: SidebarProps) {
  const [search, setSearch] = useState('');

  // Filter docs based on search term
  const filteredGroups = useMemo(() => {
    if (!search.trim()) return groupedDocs;

    const query = search.toLowerCase();
    const filtered: Record<string, DocEntry[]> = {};

    Object.keys(groupedDocs).forEach(section => {
      const matches = groupedDocs[section].filter(doc => 
        doc.data.title.toLowerCase().includes(query)
      );
      if (matches.length > 0) {
        filtered[section] = matches;
      }
    });

    return filtered;
  }, [search, groupedDocs]);

  return (
    <aside className="hidden md:flex flex-col w-64 fixed inset-y-0 left-0 pt-24 pb-8 px-6 bg-surface-base border-r border-border-subtle z-30">
      {/* Search Input */}
      <div className="relative mb-6">
        <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
          <svg className="h-4 w-4 text-text-tertiary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        <input
          type="text"
          placeholder="Search manual..."
          className="block w-full pl-10 pr-3 py-2 border border-border-default rounded-md leading-5 bg-surface-paper text-text-primary placeholder-text-tertiary focus:outline-none focus:ring-2 focus:ring-focus-ring focus:border-focus sm:text-sm transition-shadow duration-200"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto space-y-8 no-scrollbar">
        {sections.map(section => {
          const docs = filteredGroups[section];
          if (!docs || docs.length === 0) return null;

          return (
            <div key={section} className="space-y-3">
              <h5 className="text-xs font-bold text-text-tertiary uppercase tracking-wider">
                {section}
              </h5>
              <ul className="space-y-1">
                {docs.map(doc => {
                  const isActive = currentSlug === doc.slug;
                  return (
                    <li key={doc.slug}>
                      <a
                        href={`/manual/${doc.slug}`}
                        className={`block px-2 py-1.5 -mx-2 rounded-md text-sm transition-all duration-200 ${
                          isActive
                            ? 'bg-surface-subtle text-brand-primary font-medium'
                            : 'text-text-secondary hover:text-text-primary hover:bg-surface-paper'
                        }`}
                      >
                        {doc.data.title}
                      </a>
                    </li>
                  );
                })}
              </ul>
            </div>
          );
        })}
        
        {Object.keys(filteredGroups).length === 0 && (
          <div className="text-sm text-text-tertiary text-center py-4">
            No results found
          </div>
        )}
      </nav>
    </aside>
  );
}
