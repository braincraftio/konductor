import React from 'react';

export const HierarchyDiagram = () => {
  return (
    <div className="my-8 rounded-xl border border-border-default bg-surface-raised shadow-lg relative overflow-hidden transition-all duration-300 hover:shadow-xl">
      {/* Background decoration */}
      <div className="absolute top-0 right-0 p-4 opacity-[0.12] dark:opacity-[0.05] font-mono text-6xl font-bold text-text-primary select-none pointer-events-none">
        HIERARCHY
      </div>
      
      {/* Content */}
      <div className="relative z-10 p-6 font-mono text-sm md:text-base space-y-1">
        
        {/* Level 0: Base */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-slate-100 text-slate-700 border border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 shadow-sm text-xs">0</div>
          <div className="pt-1">
            <code className="text-slate-700 bg-slate-50 border-slate-100 dark:text-slate-200 font-bold dark:bg-slate-800/50 px-1.5 py-0.5 rounded border dark:border-slate-700">base</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Default Shell (Core Tools)</div>
          </div>
        </div>

        {/* Connector */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Level 1: Languages (Parallel) */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-blue-100 text-blue-700 border border-blue-200 dark:bg-sky-900/30 dark:text-sky-300 dark:border-sky-800 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 shadow-sm text-xs">1</div>
          <div className="pt-1 w-full">
            <div className="flex flex-wrap gap-2 mb-1">
                <code className="text-blue-700 bg-blue-50 border-blue-100 dark:text-sky-300 dark:bg-sky-900/20 px-1.5 py-0.5 rounded border dark:border-sky-800/50 font-bold">python</code>
                <code className="text-cyan-700 bg-cyan-50 border-cyan-100 dark:text-cyan-300 dark:bg-cyan-900/20 px-1.5 py-0.5 rounded border dark:border-cyan-800/50 font-bold">go</code>
                <code className="text-green-700 bg-green-50 border-green-100 dark:text-emerald-300 dark:bg-emerald-900/20 px-1.5 py-0.5 rounded border dark:border-emerald-800/50 font-bold">node</code>
                <code className="text-orange-700 bg-orange-50 border-orange-100 dark:text-orange-300 dark:bg-orange-900/20 px-1.5 py-0.5 rounded border dark:border-orange-800/50 font-bold">rust</code>
                <code className="text-purple-700 bg-purple-50 border-purple-100 dark:text-purple-300 dark:bg-purple-900/20 px-1.5 py-0.5 rounded border dark:border-purple-800/50 font-bold">dev</code>
            </div>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Specialized Environments (Base + Language + Tools)</div>
          </div>
        </div>

        {/* Connector */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Level 2: Full (Parallel with CI) */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-violet-100 text-violet-700 border border-violet-200 dark:bg-violet-900/30 dark:text-violet-300 dark:border-violet-800 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 shadow-sm text-xs">2</div>
          <div className="pt-1 w-full">
            <div className="flex flex-wrap gap-2 mb-1">
              <code className="text-violet-700 bg-violet-50 border-violet-100 dark:text-violet-300 font-bold dark:bg-violet-900/20 px-1.5 py-0.5 rounded border dark:border-violet-800/50">full</code>
              <code className="text-indigo-700 bg-indigo-50 border-indigo-100 dark:text-indigo-300 font-bold dark:bg-indigo-900/20 px-1.5 py-0.5 rounded border dark:border-indigo-800/50">ci</code>
            </div>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Polyglot & CI/CD Environments (Base + All Languages + Tools)</div>
          </div>
        </div>

        {/* Connector */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Level 3: Konductor & Frontend (Parallel) */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-pink-100 text-pink-700 border border-pink-200 dark:bg-pink-900/30 dark:text-pink-300 dark:border-pink-800 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 shadow-sm text-xs">3</div>
          <div className="pt-1 w-full">
            <div className="flex flex-wrap gap-2 mb-1">
              <code className="text-pink-700 bg-pink-50 border-pink-100 dark:text-pink-300 font-bold dark:bg-pink-900/20 px-1.5 py-0.5 rounded border dark:border-pink-800/50">konductor</code>
              <code className="text-rose-700 bg-rose-50 border-rose-100 dark:text-rose-300 font-bold dark:bg-rose-900/20 px-1.5 py-0.5 rounded border dark:border-rose-800/50">frontend</code>
            </div>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Advanced Environments (Extends Full)</div>
          </div>
        </div>

      </div>
    </div>
  );
};
