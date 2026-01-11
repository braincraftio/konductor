import React from 'react';
import CodeBlock from './CodeBlock';

export const Pre = (props: any) => {
    return (
        <CodeBlock className="my-8">
            <pre {...props} className={`${props.className || ''} !my-0`} />
        </CodeBlock>
    );
};

export const Card = ({ children, title, icon, className = '' }: { children: React.ReactNode, title?: string, icon?: string, className?: string }) => {
    return (
        <div className={`p-6 bg-surface-paper border border-border-default rounded-xl shadow-sm hover:shadow-md transition-shadow duration-300 not-prose ${className}`}>
            {icon && <div className="text-3xl mb-4">{icon}</div>}
            {title && <h3 className="text-lg font-bold text-text-primary mb-2">{title}</h3>}
            <div className="text-text-secondary leading-relaxed">{children}</div>
        </div>
    );
};

export const CardGrid = ({ children }: { children: React.ReactNode }) => {
    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 my-8 not-prose">
            {children}
        </div>
    );
};

export const FeatureList = ({ items }: { items: { title: string, description: string, icon?: string }[] }) => {
    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 my-8 not-prose">
            {items.map((item, idx) => (
                <div key={idx} className="flex gap-4 p-4 rounded-lg bg-surface-subtle/50 border border-border-subtle hover:bg-surface-subtle transition-colors duration-200">
                    {item.icon && (
                        <div className="flex-shrink-0 w-10 h-10 flex items-center justify-center rounded-full bg-brand-primary/10 text-brand-primary">
                            {item.icon}
                        </div>
                    )}
                    <div>
                        <h4 className="text-base font-bold text-text-primary mb-1">{item.title}</h4>
                        <p className="text-sm text-text-secondary leading-relaxed">{item.description}</p>
                    </div>
                </div>
            ))}
        </div>
    );
};

export const Note = ({ children, type = 'info', title }: { children: React.ReactNode, type?: 'info' | 'warning' | 'danger' | 'success', title?: string }) => {
    const styles = {
        info: "bg-info-bg border-info-border text-text-secondary",
        warning: "bg-warning-bg border-warning-border text-text-secondary",
        danger: "bg-danger-bg border-danger-border text-text-secondary",
        success: "bg-success-bg border-success-border text-text-secondary"
    };

    const icons = {
        info: "ℹ️",
        warning: "⚠️",
        danger: "🚨",
        success: "✅"
    };

    return (
        <div className={`my-8 p-4 rounded-lg border-l-4 ${styles[type]} not-prose`}>
            <div className="flex gap-3">
                <div className="flex-shrink-0 text-xl">{icons[type]}</div>
                <div>
                    {title && <h5 className="font-bold text-text-primary mb-1">{title}</h5>}
                    <div className="text-sm leading-relaxed">
                        {children}
                    </div>
                </div>
            </div>
        </div>
    );
};
