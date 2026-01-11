import React, { useState, useEffect, useMemo } from 'react';
import { 
  Search, 
  Rocket, 
  Brain, 
  Compass, 
  Code, 
  Menu,
  X,
  Home
} from 'lucide-react';

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

const SECTION_ICONS: Record<string, React.ElementType> = {
  'Getting Started': Rocket,
  'Core Concepts': Brain,
  'Guides': Compass,
  'Reference': Code,
};

// Simple utility to normalize slugs for reliable comparison
const normalizeSlug = (slug: string) => slug.replace(/^\/|\/$/g, '').toLowerCase();

export default function Sidebar({ sections, groupedDocs, currentSlug }: SidebarProps) {
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [search, setSearch] = useState('');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [activeFlyout, setActiveFlyout] = useState<string | null>(null);
  const [searchFlyoutOpen, setSearchFlyoutOpen] = useState(false);

  // Normalize current slug for comparison
  const normalizedCurrentSlug = normalizeSlug(currentSlug);

  // Handle CSS variable for layout
  useEffect(() => {
    // Only update on desktop breakpoint
    const updateLayout = () => {
        if (window.innerWidth >= 768) {
            const width = isCollapsed ? '5rem' : '16rem';
            document.documentElement.style.setProperty('--sidebar-width', width);
        } else {
            // On mobile, sidebar is fixed/overlay, so layout padding should be 0 or standard
            document.documentElement.style.removeProperty('--sidebar-width');
        }
    };

    updateLayout();
    window.addEventListener('resize', updateLayout);
    return () => window.removeEventListener('resize', updateLayout);
  }, [isCollapsed]);

  // Filter docs based on search term
  const filteredGroups = useMemo(() => {
    if (!search.trim()) return groupedDocs;
    const query = search.toLowerCase();
    const filtered: Record<string, DocEntry[]> = {};
    Object.keys(groupedDocs).forEach(section => {
      const matches = groupedDocs[section].filter(doc => 
        doc.data.title.toLowerCase().includes(query)
      );
      if (matches.length > 0) filtered[section] = matches;
    });
    return filtered;
  }, [search, groupedDocs]);

  return (
    <>
      {/* Mobile Menu Toggle - Visible only on small screens */}
      <div className="fixed top-24 left-4 z-[60] md:hidden">
        <button 
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          className="p-2 surface-paper-solid border border-border-default rounded-md shadow-sm text-text-secondary"
        >
          {mobileMenuOpen ? <X size={20} /> : <Menu size={20} />}
        </button>
      </div>

      {/* Sidebar Container */}
      <aside 
        className={`
          fixed inset-y-0 left-0 z-[60] pt-0 sidebar-solid border-r border-border-subtle transition-all duration-300 ease-spring flex flex-col
          ${mobileMenuOpen ? 'translate-x-0 w-64 shadow-xl' : '-translate-x-full md:translate-x-0'}
          ${isCollapsed ? 'md:w-20' : 'md:w-64'}
        `}
      >
        {/* Top Control Bar (Within Sidebar) */}
        <div className={`
           h-20 flex items-center border-b border-border-subtle shrink-0 transition-all duration-300 z-[61] sidebar-solid
           ${isCollapsed ? 'justify-center px-0' : 'px-4'}
        `}>
           {/* Unified Toggle/Brand Button */}
           <button
              onClick={() => setIsCollapsed(!isCollapsed)}
              className={`
                group flex items-center justify-center rounded-xl transition-all duration-300 ease-spring shadow-sm hover:shadow-md
                font-bold font-sans btn-sidebar-toggle
                ${isCollapsed ? 'w-12 h-12 p-0' : 'w-full h-12 px-0'}
              `}
              title={isCollapsed ? "Expand Sidebar" : "Collapse Sidebar"}
           >
              <div className="flex items-baseline text-lg">
                <span>K</span>
                <span className={`
                  overflow-hidden transition-all duration-500 ease-in-out whitespace-nowrap
                  ${isCollapsed ? 'max-w-0 opacity-0' : 'max-w-[200px] opacity-100'}
                `}>
                  onductor.sh
                </span>
              </div>
           </button>
        </div>
        
        {/* 
            Sidebar Content 
            CRITICAL FIX: 
            We need overflow-visible when collapsed so flyouts can pop out.
            We need overflow-hidden (or auto) when expanded so we can scroll the list.
        */}
        <div className={`flex-1 flex flex-col p-4 ${isCollapsed ? 'overflow-visible' : 'overflow-hidden'}`}>
          
          {/* Navigation Container */}
          <nav className={`flex-1 ${isCollapsed ? 'overflow-visible' : 'overflow-y-auto no-scrollbar'} space-y-2 pb-20`}>

            {/* 1. Search UI (MOVED TO TOP) */}
            <div 
              className={`relative mb-2 transition-all duration-300 ${isCollapsed ? 'mt-4' : 'mt-4'}`}
              onMouseEnter={() => isCollapsed && setSearchFlyoutOpen(true)}
              onMouseLeave={() => isCollapsed && setSearchFlyoutOpen(false)}
            >
              {!isCollapsed ? (
                // EXPANDED: Standard Input
                <div className="relative group">
                  <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <Search size={16} className="text-text-tertiary group-focus-within:text-brand-primary transition-colors" />
                  </div>
                  <input
                    type="text"
                    placeholder="Search docs..."
                    className="block w-full pl-9 pr-3 py-2 border border-border-default rounded-lg text-sm bg-surface-paper text-text-primary placeholder-text-tertiary focus:outline-none focus:ring-2 focus:ring-focus-ring focus:border-focus transition-all shadow-sm"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                  />
                </div>
              ) : (
                // COLLAPSED: Icon Trigger + Flyout
                <div className="flex justify-center relative group">
                  <button 
                    className={`
                      p-2 rounded-lg transition-colors
                      ${searchFlyoutOpen || search.length > 0 
                        ? 'text-brand-primary bg-surface-subtle' 
                        : 'text-text-tertiary hover:text-brand-primary hover:bg-surface-subtle'
                      }
                    `}
                  >
                    <Search size={24} />
                  </button>
                  
                  {/* Search Flyout */}
                  <div className={`
                    flyout-menu
                    absolute left-full top-0 ml-3 w-72 border border-border-default rounded-xl shadow-2xl p-3 z-[100] 
                    origin-left transition-all duration-200 ease-out text-slate-800 dark:text-cream-100
                    ${searchFlyoutOpen ? 'opacity-100 scale-100 visible' : 'opacity-0 scale-95 invisible'}
                  `}>
                    <div className="relative">
                      <Search size={16} className="absolute left-3 top-3 text-text-tertiary" />
                      <input
                        type="text"
                        placeholder="Search..."
                        autoFocus={searchFlyoutOpen}
                        className="w-full pl-9 pr-3 py-2 bg-surface-paper border border-border-subtle rounded-lg text-sm text-text-primary focus:outline-none focus:ring-2 focus:ring-brand-primary mb-2"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                      />
                    </div>
                    {/* Tiny Results Preview in Flyout */}
                    {search.trim() && (
                      <div className="max-h-60 overflow-y-auto space-y-1 mt-2 pr-1">
                        {Object.entries(filteredGroups).map(([section, docs]) => (
                           docs.length > 0 && (
                             <div key={section}>
                               <div className="text-[10px] uppercase font-bold text-text-tertiary mb-1 mt-2 px-2">{section}</div>
                               {docs.map(doc => (
                                 <a 
                                   key={doc.slug}
                                   href={`/manual/${doc.slug}`}
                                   className="block px-2 py-1.5 text-sm text-text-secondary hover:text-brand-primary hover:bg-surface-subtle rounded cursor-pointer truncate"
                                 >
                                   {doc.data.title}
                                 </a>
                               ))}
                             </div>
                           )
                        ))}
                        {Object.keys(filteredGroups).length === 0 && (
                          <div className="px-2 py-4 text-center text-xs text-text-tertiary">No results found</div>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
            
            {/* 2. Home Link (MOVED BELOW SEARCH) */}
            <div className="relative group">
               <a 
                 href="/"
                 className={`
                    flex items-center gap-3 mb-1 rounded-lg transition-colors
                    ${isCollapsed 
                      ? 'justify-center py-3 text-text-tertiary hover:bg-surface-subtle hover:text-brand-primary' 
                      : 'px-2 py-2 text-text-secondary hover:text-text-primary hover:bg-surface-subtle'
                    }
                 `}
                 title={isCollapsed ? "Home" : ""}
               >
                 <Home size={isCollapsed ? 24 : 18} />
                 {!isCollapsed && <span className="text-sm font-medium">Home</span>}
               </a>
               {/* No Tooltip for Home anymore */}
            </div>

            {/* 3. Doc Sections */}
            {sections.map(section => {
              const docs = filteredGroups[section];
              if (!docs || docs.length === 0) return null;
              
              const Icon = SECTION_ICONS[section] || Code;
              const isActiveGroup = docs.some(d => normalizeSlug(d.slug) === normalizedCurrentSlug);

              return (
                <div 
                  key={section} 
                  className="relative group"
                  onMouseEnter={() => isCollapsed && setActiveFlyout(section)}
                  onMouseLeave={() => isCollapsed && setActiveFlyout(null)}
                >
                  {/* Section Header / Icon */}
                  <div className={`
                      flex items-center gap-3 mb-1 text-text-tertiary rounded-lg transition-colors
                      ${isCollapsed 
                        ? 'justify-center py-3 hover:bg-surface-subtle cursor-pointer' 
                        : 'px-2 py-1'
                      }
                  `}>
                    <Icon 
                        size={isCollapsed ? 24 : 16} 
                        className={`transition-colors duration-200 ${isActiveGroup ? 'text-brand-primary' : 'group-hover:text-text-primary'}`} 
                    />
                    {!isCollapsed && (
                      <h5 className="text-xs font-bold uppercase tracking-wider whitespace-nowrap overflow-hidden">
                        {section}
                      </h5>
                    )}
                  </div>

                  {/* Links List - Desktop Flyout when collapsed */}
                  {isCollapsed ? (
                      /* Flyout Menu (Only visible on Hover/Focus) */
                      <ul 
                        className={`
                          flyout-menu
                          absolute left-full top-0 ml-3 w-64 border border-border-default rounded-xl shadow-2xl p-4 z-[100] 
                          transition-all duration-200 ease-spring origin-left text-slate-800 dark:text-cream-100
                          ${activeFlyout === section ? 'opacity-100 scale-100 visible' : 'opacity-0 scale-95 invisible'}
                        `}
                      >
                        <li className="flex items-center gap-2 pb-3 mb-3 border-b border-border-subtle text-text-primary font-bold">
                            <Icon size={18} className="text-brand-primary" />
                            {section}
                        </li>
                         {docs.map(doc => {
                            const isActive = normalizeSlug(doc.slug) === normalizedCurrentSlug;
                            return (
                                <li key={doc.slug}>
                                <a
                                    href={`/manual/${doc.slug}`}
                                    className={`
                                    block px-3 py-2 rounded-lg text-sm transition-all duration-200
                                    ${isActive 
                                        ? 'bg-surface-subtle text-brand-primary font-medium' 
                                        : 'text-text-secondary hover:text-text-primary hover:bg-surface-subtle'
                                    }
                                    `}
                                >
                                    {doc.data.title}
                                </a>
                                </li>
                            );
                        })}
                      </ul>
                  ) : (
                      /* Expanded List */
                      <ul className="space-y-0.5 ml-2 border-l border-border-subtle pl-2">
                        {docs.map(doc => {
                        const isActive = normalizeSlug(doc.slug) === normalizedCurrentSlug;
                        return (
                            <li key={doc.slug}>
                            <a
                                href={`/manual/${doc.slug}`}
                                className={`
                                block px-2 py-1.5 rounded-md text-sm transition-all duration-200
                                ${isActive 
                                    ? 'text-brand-primary font-medium bg-surface-subtle' 
                                    : 'text-text-secondary hover:text-text-primary hover:bg-surface-paper'
                                }
                                `}
                            >
                                <span className="truncate">{doc.data.title}</span>
                            </a>
                            </li>
                        );
                        })}
                    </ul>
                  )}
                </div>
              );
            })}
          </nav>
        </div>
      </aside>
      
      {/* Overlay for mobile menu */}
      {mobileMenuOpen && (
        <div 
            className="fixed inset-0 bg-black/20 backdrop-blur-sm z-[55] md:hidden"
            onClick={() => setMobileMenuOpen(false)}
        />
      )}
    </>
  );
}