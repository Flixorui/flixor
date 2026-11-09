const FILLED = { viewBox: '0 0 24 24', 'aria-hidden': true, fill: 'currentColor', xmlns: 'http://www.w3.org/2000/svg' } as const;

type IconProps = { className?: string };

export function PlayIcon({ className = 'w-9 h-9 sm:w-10 sm:h-10' }: IconProps) {
  return (
    <svg {...FILLED} className={className}>
      <path d="M5 2.69127C5 1.93067 5.81547 1.44851 6.48192 1.81506L23.4069 11.1238C24.0977 11.5037 24.0977 12.4963 23.4069 12.8762L6.48192 22.1849C5.81546 22.5515 5 22.0693 5 21.3087V2.69127Z" />
    </svg>
  );
}

export function PauseIcon({ className = 'w-9 h-9 sm:w-10 sm:h-10' }: IconProps) {
  return (
    <svg {...FILLED} className={className}>
      <path fillRule="evenodd" clipRule="evenodd" d="M4.5 3C4.22386 3 4 3.22386 4 3.5V20.5C4 20.7761 4.22386 21 4.5 21H9.5C9.77614 21 10 20.7761 10 20.5V3.5C10 3.22386 9.77614 3 9.5 3H4.5ZM14.5 3C14.2239 3 14 3.22386 14 3.5V20.5C14 20.7761 14.2239 21 14.5 21H19.5C19.7761 21 20 20.7761 20 20.5V3.5C20 3.22386 19.7761 3 19.5 3H14.5Z" />
    </svg>
  );
}

const SPEAKER = 'M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714Z';
const WAVE_NEAR = 'M16.0001 12C16.0001 10.4087 15.368 8.88262 14.2428 7.7574L12.8285 9.17161C13.5787 9.92176 14.0001 10.9392 14.0001 12C14.0001 13.0609 13.5787 14.0783 12.8285 14.8285L14.2428 16.2427C15.368 15.1175 16.0001 13.5913 16.0001 12Z';
const WAVE_MID = 'M17.0709 4.92897C18.9462 6.80433 19.9998 9.34787 19.9998 12C19.9998 14.6522 18.9462 17.1957 17.0709 19.0711L15.6567 17.6569C17.157 16.1566 17.9998 14.1218 17.9998 12C17.9998 9.87831 17.157 7.84347 15.6567 6.34318L17.0709 4.92897Z';
const WAVE_FAR = 'M24 12C24 8.28693 22.525 4.72597 19.8995 2.10046L18.4853 3.51468C20.7357 5.76511 22 8.81736 22 12C22 15.1826 20.7357 18.2348 18.4853 20.4852L19.8995 21.8995C22.525 19.2739 24 15.713 24 12Z';
const MUTE_X = 'M15.2929 9.70714L17.5858 12L15.2929 14.2929L16.7071 15.7071L19 13.4142L21.2929 15.7071L22.7071 14.2929L20.4142 12L22.7071 9.70714L21.2929 8.29292L19 10.5858L16.7071 8.29292L15.2929 9.70714Z';

export function VolumeIcon({ level, className = 'w-8 h-8' }: IconProps & { level: number }) {
  const paths = level === 0
    ? [SPEAKER, MUTE_X]
    : level <= 0.33
      ? [SPEAKER, WAVE_NEAR]
      : level <= 0.66
        ? [SPEAKER, WAVE_NEAR, WAVE_MID]
        : [SPEAKER, WAVE_NEAR, WAVE_MID, WAVE_FAR];
  return (
    <svg {...FILLED} className={className}>
      {paths.map((d) => <path key={d} fillRule="evenodd" clipRule="evenodd" d={d} />)}
    </svg>
  );
}

export function NextEpisodeIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg {...FILLED} className={className}>
      <path fillRule="evenodd" clipRule="evenodd" d="M22 3H20V21H22V3ZM4.28615 3.61729C3.28674 3.00228 2 3.7213 2 4.89478V19.1052C2 20.2787 3.28674 20.9977 4.28615 20.3827L15.8321 13.2775C16.7839 12.6918 16.7839 11.3082 15.8321 10.7225L4.28615 3.61729ZM4 18.2104V5.78956L14.092 12L4 18.2104Z" />
    </svg>
  );
}

export function EpisodesIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg {...FILLED} className={className}>
      <path fillRule="evenodd" clipRule="evenodd" d="M8 5H22V13H24V5C24 3.89543 23.1046 3 22 3H8V5ZM18 9H4V7H18C19.1046 7 20 7.89543 20 9V17H18V9ZM0 13C0 11.8954 0.895431 11 2 11H14C15.1046 11 16 11.8954 16 13V19C16 20.1046 15.1046 21 14 21H2C0.895431 21 0 20.1046 0 19V13ZM14 19V13H2V19H14Z" />
    </svg>
  );
}

export function SettingsIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg className={className} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
  );
}

export function SpeedIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg {...FILLED} className={className}>
      <path fillRule="evenodd" clipRule="evenodd" d="M19.0569 6.27006C15.1546 2.20629 8.84535 2.20629 4.94312 6.27006C1.01896 10.3567 1.01896 16.9985 4.94312 21.0852L3.50053 22.4704C-1.16684 17.6098 -1.16684 9.7454 3.50053 4.88481C8.18984 0.0013696 15.8102 0.0013696 20.4995 4.88481C25.1668 9.7454 25.1668 17.6098 20.4995 22.4704L19.0569 21.0852C22.981 16.9985 22.981 10.3567 19.0569 6.27006ZM15 14.0001C15 15.6569 13.6569 17.0001 12 17.0001C10.3431 17.0001 9 15.6569 9 14.0001C9 12.3432 10.3431 11.0001 12 11.0001C12.4632 11.0001 12.9018 11.105 13.2934 11.2924L16.2929 8.29296L17.7071 9.70717L14.7076 12.7067C14.895 13.0983 15 13.5369 15 14.0001Z" />
    </svg>
  );
}

export function SubtitlesIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg className={className} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path strokeLinecap="round" d="M6 12h3M12 12h6M6 16h8M17 16h1" />
    </svg>
  );
}

export function ChaptersIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg className={className} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden>
      <path strokeLinecap="round" d="M9 6h12M9 12h12M9 18h12" />
      <circle cx="4" cy="6" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="4" cy="12" r="1.5" fill="currentColor" stroke="none" />
      <circle cx="4" cy="18" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function SourcesIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg className={className} fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden>
      <ellipse cx="12" cy="6" rx="8" ry="3" />
      <path d="M4 6v6c0 1.66 3.58 3 8 3s8-1.34 8-3V6M4 12v6c0 1.66 3.58 3 8 3s8-1.34 8-3v-6" />
    </svg>
  );
}

export function PipIcon({ className = 'w-8 h-8' }: IconProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M3 5a2 2 0 012-2h14a2 2 0 012 2v6h-2V5H5v14h6v2H5a2 2 0 01-2-2V5z" />
      <rect x="13" y="13" width="8" height="6" rx="1" />
    </svg>
  );
}

export function FullscreenIcon({ active, className = 'w-8 h-8' }: IconProps & { active: boolean }) {
  return (
    <svg {...FILLED} className={className}>
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d={active
          ? 'M24 8H19V3H17V9V10H18H24V8ZM0 16H5V21H7V15V14H6H0V16ZM7 10H6H0V8H5V3H7V9V10ZM19 21V16H24V14H18H17V15V21H19Z'
          : 'M0 5C0 3.89543 0.895431 3 2 3H9V5H2V9H0V5ZM22 5H15V3H22C23.1046 3 24 3.89543 24 5V9H22V5ZM2 15V19H9V21H2C0.895431 21 0 20.1046 0 19V15H2ZM22 19V15H24V19C24 20.1046 23.1046 21 22 21H15V19H22Z'}
      />
    </svg>
  );
}

export function BackIcon({ className = 'w-6 h-6' }: IconProps) {
  return (
    <svg className={className} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
    </svg>
  );
}
