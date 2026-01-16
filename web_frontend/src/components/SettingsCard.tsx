import { ReactNode } from 'react';

type SettingsCardProps = {
  title?: string;
  children: ReactNode;
  className?: string;
};

/**
 * Settings card container - matches Mobile React Native implementation exactly
 * Container with title label and rounded card with semi-transparent background
 */
export default function SettingsCard({ title, children, className = '' }: SettingsCardProps) {
  return (
    <div className={`mb-[18px] ${className}`}>
      {title && (
        <span
          className="block text-[#9ca3af] text-[12px] font-bold tracking-[1px] uppercase ml-1 mb-2"
        >
          {title}
        </span>
      )}
      <div
        className="rounded-[14px] overflow-hidden"
        style={{
          backgroundColor: 'rgba(17,17,20,0.92)',
          border: '1px solid rgba(255,255,255,0.06)',
        }}
      >
        {children}
      </div>
    </div>
  );
}

/**
 * Section header for grouping within settings
 * Used inside a SettingsCard to subdivide content
 */
export function SettingsSectionHeader({ title }: { title: string }) {
  return (
    <div className="px-[14px] pt-4 pb-2">
      <span className="text-[11px] font-medium text-[#9ca3af] uppercase tracking-wide">
        {title}
      </span>
    </div>
  );
}
