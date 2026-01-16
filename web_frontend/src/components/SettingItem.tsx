import { ReactNode } from 'react';

type SettingItemProps = {
  title: string;
  description?: string;
  icon?: ReactNode;
  renderIcon?: () => ReactNode;
  renderRight?: () => ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  isLast?: boolean;
  className?: string;
};

/**
 * Individual setting item - matches Mobile React Native implementation exactly
 * Row with icon, title/description, and optional right control
 */
export default function SettingItem({
  title,
  description,
  icon,
  renderIcon,
  renderRight,
  onClick,
  disabled = false,
  isLast = false,
  className = '',
}: SettingItemProps) {
  const isClickable = !!onClick && !disabled;

  const content = (
    <>
      {/* Icon wrapper - 34x34 with 10px radius */}
      {renderIcon ? (
        <div className="mr-3 flex-shrink-0">
          {renderIcon()}
        </div>
      ) : (icon || null) ? (
        <div
          className="flex items-center justify-center w-[34px] h-[34px] rounded-[10px] mr-3 flex-shrink-0"
          style={{ backgroundColor: 'rgba(229,231,235,0.08)' }}
        >
          {icon}
        </div>
      ) : null}

      {/* Text content */}
      <div className="flex-1 min-w-0">
        <span className="block text-[#f9fafb] text-[15px] font-semibold truncate">
          {title}
        </span>
        {description && (
          <span className="block text-[#9ca3af] text-[12px] truncate mt-0.5">
            {description}
          </span>
        )}
      </div>

      {/* Right element */}
      {renderRight && (
        <div className="flex-shrink-0 ml-2">
          {renderRight()}
        </div>
      )}
    </>
  );

  const baseStyles = `
    flex items-center
    px-[14px] py-[14px]
    ${!isLast ? 'border-b border-white/[0.08]' : ''}
    ${disabled ? 'opacity-50' : ''}
    ${className}
  `;

  if (isClickable) {
    return (
      <button
        onClick={onClick}
        disabled={disabled}
        className={`
          ${baseStyles}
          w-full text-left
          transition-colors
          hover:bg-white/[0.04]
          active:bg-white/[0.08]
          disabled:cursor-not-allowed
        `}
      >
        {content}
      </button>
    );
  }

  return (
    <div className={baseStyles}>
      {content}
    </div>
  );
}

/**
 * Toggle switch component - iOS style matching mobile
 */
export function SettingToggle({
  checked,
  onChange,
  disabled = false,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`
        relative inline-flex h-[31px] w-[51px] flex-shrink-0
        cursor-pointer rounded-full
        transition-colors duration-200 ease-in-out
        focus:outline-none focus:ring-2 focus:ring-green-500/50 focus:ring-offset-2 focus:ring-offset-transparent
        disabled:opacity-50 disabled:cursor-not-allowed
        ${checked ? 'bg-[#34c759]' : 'bg-white/20'}
      `}
    >
      <span
        className={`
          pointer-events-none inline-block h-[27px] w-[27px]
          transform rounded-full bg-white shadow-lg
          transition duration-200 ease-in-out
          mt-[2px]
          ${checked ? 'translate-x-[22px]' : 'translate-x-[2px]'}
        `}
      />
    </button>
  );
}

/**
 * Select/picker component for settings - pill style
 */
export function SettingSelect<T extends string>({
  value,
  options,
  onChange,
  disabled = false,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value as T)}
      disabled={disabled}
      className={`
        bg-white/10 border border-white/10
        rounded-lg px-3 py-1.5
        text-sm text-white font-medium
        focus:outline-none focus:ring-2 focus:ring-blue-500/50
        disabled:opacity-50 disabled:cursor-not-allowed
        min-w-[100px]
        appearance-none cursor-pointer
      `}
      style={{
        backgroundImage: `url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 20 20'%3e%3cpath stroke='%239ca3af' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5' d='M6 8l4 4 4-4'/%3e%3c/svg%3e")`,
        backgroundPosition: 'right 8px center',
        backgroundRepeat: 'no-repeat',
        backgroundSize: '16px',
        paddingRight: '32px',
      }}
    >
      {options.map((opt) => (
        <option key={opt.value} value={opt.value} className="bg-[#1a1a1a]">
          {opt.label}
        </option>
      ))}
    </select>
  );
}

/**
 * Segmented control - matches mobile pill toggle style
 */
export function SettingSegmentedControl<T extends string>({
  value,
  options,
  onChange,
  disabled = false,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  return (
    <div
      className={`
        flex rounded-[14px] p-0.5 gap-0.5
        ${disabled ? 'opacity-50 cursor-not-allowed' : ''}
      `}
      style={{
        backgroundColor: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.12)',
      }}
    >
      {options.map((opt) => (
        <button
          key={opt.value}
          onClick={() => !disabled && onChange(opt.value)}
          disabled={disabled}
          className={`
            px-4 py-2 text-[13px] font-semibold rounded-[10px]
            transition-all duration-200
            ${
              value === opt.value
                ? 'bg-white text-black'
                : 'text-[#9ca3af] hover:text-white'
            }
          `}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

/**
 * Text input for settings
 */
export function SettingInput({
  value,
  onChange,
  placeholder,
  type = 'text',
  disabled = false,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: 'text' | 'password' | 'url';
  disabled?: boolean;
}) {
  return (
    <input
      type={type}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      disabled={disabled}
      className={`
        bg-white/10 border border-white/10
        rounded-lg px-3 py-2
        text-sm text-white placeholder:text-white/40
        focus:outline-none focus:ring-2 focus:ring-blue-500/50
        disabled:opacity-50 disabled:cursor-not-allowed
        w-full max-w-xs
      `}
    />
  );
}

/**
 * Status badge for connection status
 */
export function SettingStatusBadge({
  status,
}: {
  status: 'connected' | 'disconnected' | 'error' | 'loading';
}) {
  const styles: Record<string, string> = {
    connected: 'bg-[#22c55e]/20 text-[#22c55e]',
    disconnected: 'bg-white/10 text-white/50',
    error: 'bg-[#ef4444]/20 text-[#ef4444]',
    loading: 'bg-[#3b82f6]/20 text-[#3b82f6]',
  };

  const labels: Record<string, string> = {
    connected: 'Connected',
    disconnected: 'Not Connected',
    error: 'Error',
    loading: 'Connecting...',
  };

  return (
    <span className={`px-2 py-1 rounded-md text-[11px] font-semibold ${styles[status]}`}>
      {labels[status]}
    </span>
  );
}

/**
 * Button for settings actions
 */
export function SettingButton({
  children,
  onClick,
  variant = 'secondary',
  disabled = false,
  loading = false,
}: {
  children: ReactNode;
  onClick: () => void;
  variant?: 'primary' | 'secondary' | 'danger';
  disabled?: boolean;
  loading?: boolean;
}) {
  const styles: Record<string, string> = {
    primary: 'bg-[#3b82f6] hover:bg-[#2563eb] text-white',
    secondary: 'bg-white/10 hover:bg-white/20 text-white',
    danger: 'bg-[#ef4444]/20 hover:bg-[#ef4444]/30 text-[#ef4444]',
  };

  return (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      className={`
        px-4 py-2 rounded-lg
        text-[13px] font-semibold
        transition-colors
        disabled:opacity-50 disabled:cursor-not-allowed
        ${styles[variant]}
      `}
    >
      {loading ? (
        <span className="flex items-center gap-2">
          <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          Loading...
        </span>
      ) : (
        children
      )}
    </button>
  );
}

/**
 * Chevron icon for navigation items
 */
export function ChevronRight({ className = '' }: { className?: string }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      className={`text-white/30 ${className}`}
    >
      <polyline points="9,18 15,12 9,6" />
    </svg>
  );
}
