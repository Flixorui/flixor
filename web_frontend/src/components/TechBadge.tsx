type TechBadgeProps = {
  codec?: string;
  resolution?: string;
  hdr?: string;
  audio?: string;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
};

// Image badge types that have PNG assets
type ImageBadgeType = '4k' | 'hd' | 'hdr' | 'hdr10plus' | 'dolby-vision' | 'dolby-atmos' | 'cc' | 'sdh' | 'ad';

const badgeImageMap: Record<string, ImageBadgeType> = {
  // Resolution
  '4k': '4k',
  '2160p': '4k',
  'uhd': '4k',
  'hd': 'hd',
  '1080p': 'hd',
  '720p': 'hd',
  // HDR
  'dovi': 'dolby-vision',
  'dolby vision': 'dolby-vision',
  'dolbyvision': 'dolby-vision',
  'hdr10+': 'hdr10plus',
  'hdr10plus': 'hdr10plus',
  'hdr10': 'hdr',
  'hdr': 'hdr',
  'hlg': 'hdr',
  // Audio
  'atmos': 'dolby-atmos',
  'dolby atmos': 'dolby-atmos',
  'truehd atmos': 'dolby-atmos',
  // Accessibility
  'cc': 'cc',
  'sdh': 'sdh',
  'ad': 'ad',
};

const codecLabels: Record<string, string> = {
  h264: 'H.264',
  avc: 'H.264',
  hevc: 'HEVC',
  h265: 'HEVC',
  av1: 'AV1',
  vp9: 'VP9',
  mpeg4: 'MPEG4',
  mpeg2video: 'MPEG2',
};

const audioLabels: Record<string, string> = {
  truehd: 'TrueHD',
  'truehd atmos': 'Atmos',
  atmos: 'Atmos',
  'dolby atmos': 'Atmos',
  dts: 'DTS',
  'dts-hd ma': 'DTS-HD MA',
  'dts:x': 'DTS:X',
  'dts-x': 'DTS:X',
  ac3: 'AC3',
  eac3: 'EAC3',
  aac: 'AAC',
  flac: 'FLAC',
};

function getResolutionLabel(width?: number, height?: number, resolution?: string): string | null {
  if (resolution) {
    const res = resolution.toLowerCase();
    if (res.includes('4k') || res.includes('2160')) return '4k';
    if (res.includes('1440')) return '1440p';
    if (res.includes('1080')) return 'hd';
    if (res.includes('720')) return 'hd';
    if (res.includes('480') || res.includes('sd')) return '480p';
    return resolution.toUpperCase();
  }
  if (height) {
    if (height >= 2160) return '4k';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return 'hd';
    if (height >= 720) return 'hd';
    if (height >= 480) return '480p';
    return `${height}p`;
  }
  if (width) {
    if (width >= 3840) return '4k';
    if (width >= 2560) return '1440p';
    if (width >= 1920) return 'hd';
    if (width >= 1280) return 'hd';
    return 'SD';
  }
  return null;
}

// Size presets matching Mobile (18px default height, width scales ~2.5x)
const sizeClasses = {
  sm: 'h-3.5', // 14px - compact for hero
  md: 'h-[18px]', // 18px (Mobile default)
  lg: 'h-6', // 24px
};

type ImageBadgeProps = {
  type: ImageBadgeType;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
};

function ImageBadge({ type, size = 'md', className = '' }: ImageBadgeProps) {
  return (
    <img
      src={`/badges/${type}.png`}
      alt={type.toUpperCase()}
      className={`${sizeClasses[size]} w-auto object-contain ${className}`}
      loading="lazy"
    />
  );
}

type TextBadgeProps = {
  label: string;
  variant?: 'default' | 'highlight' | 'hdr';
  size?: 'sm' | 'md' | 'lg';
};

function TextBadge({ label, variant = 'default', size = 'md' }: TextBadgeProps) {
  const sizeTextClasses = {
    sm: 'px-1 py-px text-[9px]',
    md: 'px-2 py-0.5 text-xs',
    lg: 'px-2.5 py-1 text-sm',
  };
  const variantClasses = {
    default: 'bg-white/10 text-white/90',
    highlight: 'bg-white/20 text-white',
    hdr: 'bg-gradient-to-r from-yellow-500/80 to-orange-500/80 text-white',
  };

  return (
    <span className={`${sizeTextClasses[size]} font-semibold rounded ${variantClasses[variant]}`}>
      {label}
    </span>
  );
}

export default function TechBadge({ codec, resolution, hdr, audio, className = '', size = 'md' }: TechBadgeProps) {
  const badges: React.ReactNode[] = [];

  // Resolution badge (image-based for 4K/HD)
  const resLabel = getResolutionLabel(undefined, undefined, resolution);
  if (resLabel) {
    const imageType = badgeImageMap[resLabel.toLowerCase()];
    if (imageType) {
      badges.push(<ImageBadge key="res" type={imageType} size={size} />);
    } else {
      badges.push(<TextBadge key="res" label={resLabel} variant="default" size={size} />);
    }
  }

  // HDR badge (image-based)
  if (hdr) {
    const hdrKey = hdr.toLowerCase();
    const imageType = badgeImageMap[hdrKey];
    if (imageType) {
      badges.push(<ImageBadge key="hdr" type={imageType} size={size} />);
    } else {
      badges.push(<TextBadge key="hdr" label={hdr.toUpperCase()} variant="hdr" size={size} />);
    }
  }

  // Audio badge (image-based for Atmos)
  if (audio) {
    const audioKey = audio.toLowerCase();
    const imageType = badgeImageMap[audioKey];
    if (imageType) {
      badges.push(<ImageBadge key="audio" type={imageType} size={size} />);
    } else {
      const audioLabel = audioLabels[audioKey] || audio.toUpperCase();
      badges.push(
        <TextBadge
          key="audio"
          label={audioLabel}
          variant={audioLabel === 'Atmos' || audioLabel === 'DTS:X' ? 'highlight' : 'default'}
          size={size}
        />
      );
    }
  }

  if (badges.length === 0) return null;

  return (
    <div className={`flex flex-wrap items-center gap-2 ${className}`}>
      {badges}
    </div>
  );
}

// Helper function to extract tech info from Plex media metadata
export function extractTechInfo(media: any): TechBadgeProps {
  if (!media) return {};

  const videoStream = media.Part?.[0]?.Stream?.find((s: any) => s.streamType === 1);
  const audioStream = media.Part?.[0]?.Stream?.find((s: any) => s.streamType === 2);

  let hdrType: string | undefined;
  if (videoStream?.DOVIPresent) {
    hdrType = 'dolby vision';
  } else if (videoStream?.colorTrc) {
    const trc = videoStream.colorTrc.toLowerCase();
    if (trc.includes('smpte2084') || trc.includes('pq')) {
      hdrType = videoStream?.colorPrimaries?.includes('2020') ? 'hdr10' : 'hdr';
    } else if (trc.includes('hlg')) {
      hdrType = 'hlg';
    }
  }

  let audioType: string | undefined;
  if (audioStream?.codec) {
    const codec = audioStream.codec.toLowerCase();
    const profile = (audioStream.profile || '').toLowerCase();
    if (codec === 'truehd' && profile.includes('atmos')) {
      audioType = 'dolby atmos';
    } else if (codec === 'eac3' && profile.includes('atmos')) {
      audioType = 'dolby atmos';
    } else {
      audioType = audioStream.codec;
    }
  }

  return {
    codec: videoStream?.codec,
    resolution: media.videoResolution || (videoStream?.height ? `${videoStream.height}p` : undefined),
    hdr: hdrType,
    audio: audioType,
  };
}

// Compact badge display for hero sections
export function TechBadgeCompact({
  resolution,
  hdr,
  audioCodec,
  className = '',
  size = 'md',
}: Pick<TechBadgeProps, 'resolution' | 'hdr' | 'className' | 'size'> & { audioCodec?: string }) {
  const badges: React.ReactNode[] = [];

  const resLabel = getResolutionLabel(undefined, undefined, resolution);
  if (resLabel) {
    const imageType = badgeImageMap[resLabel.toLowerCase()];
    if (imageType) {
      badges.push(<ImageBadge key="res" type={imageType} size={size} />);
    } else {
      badges.push(<TextBadge key="res" label={resLabel} variant="default" size={size} />);
    }
  }

  if (hdr) {
    const hdrKey = hdr.toLowerCase();
    const imageType = badgeImageMap[hdrKey];
    if (imageType) {
      badges.push(<ImageBadge key="hdr" type={imageType} size={size} />);
    } else {
      badges.push(<TextBadge key="hdr" label={hdr.toUpperCase()} variant="hdr" size={size} />);
    }
  }

  // Audio badge for Atmos/DTS:X
  if (audioCodec) {
    const audioKey = audioCodec.toLowerCase();
    if (audioKey.includes('atmos') || audioKey.includes('truehd')) {
      badges.push(<ImageBadge key="audio" type="dolby-atmos" size={size} />);
    } else if (audioKey.includes('dts:x') || audioKey.includes('dts-x')) {
      badges.push(<TextBadge key="audio" label="DTS:X" variant="highlight" size={size} />);
    }
  }

  if (badges.length === 0) return null;

  const gapClass = size === 'sm' ? 'gap-1' : 'gap-2';
  return (
    <div className={`flex items-center ${gapClass} ${className}`}>
      {badges}
    </div>
  );
}

// Accessibility badges (CC, SDH, AD)
export function AccessibilityBadges({
  hasCC,
  hasSDH,
  hasAD,
  className = '',
  size = 'md',
}: {
  hasCC?: boolean;
  hasSDH?: boolean;
  hasAD?: boolean;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
}) {
  const badges: React.ReactNode[] = [];

  if (hasCC) badges.push(<ImageBadge key="cc" type="cc" size={size} />);
  if (hasSDH) badges.push(<ImageBadge key="sdh" type="sdh" size={size} />);
  if (hasAD) badges.push(<ImageBadge key="ad" type="ad" size={size} />);

  if (badges.length === 0) return null;

  const gapClass = size === 'sm' ? 'gap-1' : 'gap-2';
  return (
    <div className={`flex items-center ${gapClass} ${className}`}>
      {badges}
    </div>
  );
}

// Full tech info display for details page
export function TechBadgesFull({
  resolution,
  hdr,
  audio,
  codec,
  hasCC,
  hasSDH,
  hasAD,
  className = '',
  size = 'md',
}: TechBadgeProps & {
  hasCC?: boolean;
  hasSDH?: boolean;
  hasAD?: boolean;
}) {
  return (
    <div className={`flex flex-wrap items-center gap-2 ${className}`}>
      <TechBadge resolution={resolution} hdr={hdr} audio={audio} codec={codec} size={size} />
      <AccessibilityBadges hasCC={hasCC} hasSDH={hasSDH} hasAD={hasAD} size={size} />
    </div>
  );
}
