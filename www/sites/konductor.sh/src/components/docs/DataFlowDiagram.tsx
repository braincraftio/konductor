import React from 'react';

export const DataFlowDiagram = () => {
  return (
    <div className="my-8 rounded-xl border border-border-default bg-surface-raised shadow-lg relative overflow-hidden transition-all duration-300 hover:shadow-xl">
      {/* Background decoration */}
      <div className="absolute top-0 right-0 p-4 opacity-[0.12] dark:opacity-[0.05] font-mono text-6xl font-bold text-text-primary select-none pointer-events-none">
        DATA FLOW
      </div>
      
      {/* Content */}
      <div className="relative z-10 p-6 font-mono text-sm md:text-base space-y-1">
        
        {/* Step 1 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-purple-100 text-purple-700 border border-purple-200 dark:bg-brand-primary/10 dark:text-brand-primary dark:border-brand-primary/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-purple-200 dark:group-hover:bg-brand-primary/20 shadow-sm">1</div>
          <div className="pt-1">
            <code className="text-purple-700 bg-purple-50 border-purple-100 dark:text-brand-primary font-bold dark:bg-brand-primary/5 px-1.5 py-0.5 rounded border dark:border-brand-primary/10">src/lib/versions.nix</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Single Source of Truth (Data)</div>
          </div>
        </div>

        {/* Connector 1 */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Step 2 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-700 border border-emerald-200 dark:bg-brand-secondary/10 dark:text-brand-secondary dark:border-brand-secondary/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-emerald-200 dark:group-hover:bg-brand-secondary/20 shadow-sm">2</div>
          <div className="pt-1">
            <code className="text-emerald-700 bg-emerald-50 border-emerald-100 dark:text-brand-secondary font-bold dark:bg-brand-secondary/5 px-1.5 py-0.5 rounded border dark:border-brand-secondary/10">src/packages/</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Package Composition Logic</div>
          </div>
        </div>

        {/* Connector 2 */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Step 3 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-orange-100 text-orange-700 border border-orange-200 dark:bg-brand-accent/10 dark:text-brand-accent dark:border-brand-accent/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-orange-200 dark:group-hover:bg-brand-accent/20 shadow-sm">3</div>
          <div className="pt-1">
            <code className="text-orange-700 bg-orange-50 border-orange-100 dark:text-brand-accent font-bold dark:bg-brand-accent/5 px-1.5 py-0.5 rounded border dark:border-brand-accent/10">src/devshells/</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Environment Definitions</div>
          </div>
        </div>

        {/* Connector 3 */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Step 4 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-text-primary/5 text-text-primary border border-text-primary/10 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-text-primary/10 shadow-sm">4</div>
          <div className="pt-1">
            <span className="font-bold text-text-primary">Outputs</span>
            <div className="text-text-tertiary text-xs mt-1.5 font-sans flex flex-wrap gap-2">
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 border border-zinc-200 dark:border-zinc-700">DevShells</span>
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 border border-zinc-200 dark:border-zinc-700">OCI Images</span>
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 border border-zinc-200 dark:border-zinc-700">QCOW2</span>
                <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300 border border-zinc-200 dark:border-zinc-700">Modules</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
