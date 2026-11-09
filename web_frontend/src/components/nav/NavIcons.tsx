type IconProps = { size?: number; filled?: boolean };

function Svg({ size = 22, filled, children }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={filled ? 'currentColor' : 'none'}
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export function NavHomeIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1v-9.5Z" />
    </Svg>
  );
}

export function NavLibraryIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <rect x="4" y="4" width="4.5" height="16" rx="1" />
      <rect x="10.5" y="4" width="4.5" height="16" rx="1" />
      <path d="m17.3 5 3.6 14.4" />
    </Svg>
  );
}

export function NavBookmarkIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M6 4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v17l-6-4-6 4V4Z" />
    </Svg>
  );
}

export function NavFlameIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M12 3c1 3.5 5.5 5.6 5.5 11a5.5 5.5 0 0 1-11 0c0-2 1-3.5 2-4.5.3 1.5 1 2.5 2 3C10 9.5 10.5 6 12 3Z" />
    </Svg>
  );
}

export function NavSearchIcon(props: IconProps) {
  return (
    <Svg {...props} filled={false}>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-3.8-3.8" />
    </Svg>
  );
}

export function NavGearIcon(props: IconProps) {
  return (
    <Svg {...props} filled={false}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.9 2.9l-.1-.1a1.7 1.7 0 0 0-2.8 1.2V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.9-2.9l.1-.1a1.7 1.7 0 0 0-1.2-2.9H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.2-2.9l-.1-.1a2 2 0 1 1 2.9-2.9l.1.1a1.7 1.7 0 0 0 1.9.3h.1a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.9 2.9l-.1.1a1.7 1.7 0 0 0-.3 1.9v.1a1.7 1.7 0 0 0 1.5 1h.1a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.6 1Z" />
    </Svg>
  );
}

export function NavPinIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M9 3h6l-.7 7 3.7 3.5v1.5H6v-1.5L9.7 10 9 3Zm3 12v6" />
    </Svg>
  );
}
