import React from 'react';

export const DataFlowDiagram = () => {
  return (
    <div className="my-8 rounded-xl border border-border-default bg-surface-raised shadow-lg relative overflow-hidden transition-all duration-300 hover:shadow-xl">
      {/* Background decoration */}
      <div className="absolute top-0 right-0 p-4 opacity-[0.03] dark:opacity-[0.05] font-mono text-6xl font-bold text-text-primary select-none pointer-events-none">
        DATA FLOW
      </div>
      
      {/* Content */}
      <div className="relative z-10 p-6 font-mono text-sm md:text-base space-y-1">
        
        {/* Step 1 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-brand-primary/10 text-brand-primary border border-brand-primary/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-brand-primary/20 shadow-sm">1</div>
          <div className="pt-1">
            <code className="text-brand-primary font-bold bg-brand-primary/5 px-1.5 py-0.5 rounded border border-brand-primary/10">src/lib/versions.nix</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Single Source of Truth (Data)</div>
          </div>
        </div>

        {/* Connector 1 */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Step 2 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-brand-secondary/10 text-brand-secondary border border-brand-secondary/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-brand-secondary/20 shadow-sm">2</div>
          <div className="pt-1">
            <code className="text-brand-secondary font-bold bg-brand-secondary/5 px-1.5 py-0.5 rounded border border-brand-secondary/10">src/packages/</code>
            <div className="text-text-secondary text-xs mt-1.5 font-sans">Package Composition Logic</div>
          </div>
        </div>

        {/* Connector 2 */}
        <div className="pl-4 ml-[15px] h-6 border-l-2 border-border-default/50 border-dashed"></div>

        {/* Step 3 */}
        <div className="flex items-start gap-4 group">
          <div className="w-8 h-8 rounded-full bg-brand-accent/10 text-brand-accent border border-brand-accent/20 flex items-center justify-center font-bold shrink-0 transition-all duration-300 group-hover:scale-110 group-hover:bg-brand-accent/20 shadow-sm">3</div>
          <div className="pt-1">
            <code className="text-brand-accent font-bold bg-brand-accent/5 px-1.5 py-0.5 rounded border border-brand-accent/10">src/devshells/</code>
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
