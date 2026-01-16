import { Track } from '@/components/TrackPicker';
import { TechBadgeCompact, AccessibilityBadges } from '@/components/TechBadge';

export interface VersionDetail {
  id: string;
  label: string;
  audios: Track[];
  subs: Track[];
  tech: {
    resolution?: string;
    width?: number;
    height?: number;
    videoCodec?: string;
    videoProfile?: string;
    audioCodec?: string;
    audioChannels?: number;
    bitrate?: number;
    container?: string;
    fileSize?: number;
    hdr?: string;
  };
}

interface VersionPickerModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  versions: VersionDetail[];
  onSelect: (version: VersionDetail) => void;
}

export default function VersionPickerModal({
  open,
  onClose,
  title,
  versions,
  onSelect,
}: VersionPickerModalProps) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="relative z-10 w-full max-w-lg mx-4 bg-neutral-900/95 backdrop-blur-xl rounded-2xl ring-1 ring-white/10 shadow-2xl overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-white/10">
          <div>
            <h2 className="text-lg font-semibold text-white">Select Version</h2>
            <p className="text-sm text-neutral-400 mt-0.5">
              Multiple versions available for '{title}'
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-full hover:bg-white/10 transition-colors"
          >
            <svg className="w-5 h-5 text-neutral-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Version List */}
        <div className="max-h-[60vh] overflow-y-auto p-4 space-y-3">
          {versions.map((version) => (
            <VersionRow
              key={version.id}
              version={version}
              onSelect={() => onSelect(version)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function VersionRow({
  version,
  onSelect,
}: {
  version: VersionDetail;
  onSelect: () => void;
}) {
  const { tech, audios, subs } = version;

  // Determine resolution for badge
  const getResolution = () => {
    if (tech.width && tech.width >= 3800) return '4k';
    if (tech.width && tech.width >= 1900) return '1080p';
    if (tech.width && tech.width >= 1200) return '720p';
    if (tech.resolution) return tech.resolution;
    return undefined;
  };

  // Detect HDR format from profile
  const getHdrFormat = () => {
    const profile = (tech.videoProfile || '').toLowerCase();
    if (profile.includes('dolby vision') || profile.includes('dovi') || profile.includes(' dv')) return 'dolby vision';
    if (profile.includes('hdr10+')) return 'hdr10+';
    if (profile.includes('hdr10') || profile.includes('hdr 10')) return 'hdr10';
    if (profile.includes('hlg')) return 'hlg';
    if (profile.includes('hdr') || profile.includes('main 10') || profile.includes('pq')) return 'hdr';
    if (tech.hdr) return tech.hdr;
    return undefined;
  };

  // Get audio channel label
  const getAudioChannels = () => {
    if (!tech.audioChannels) return null;
    if (tech.audioChannels >= 8) return '7.1';
    if (tech.audioChannels >= 6) return '5.1';
    if (tech.audioChannels >= 2) return 'Stereo';
    return `${tech.audioChannels}CH`;
  };

  // Detect Atmos for badge
  const getAudioCodecForBadge = () => {
    const codec = (tech.audioCodec || '').toLowerCase();
    if (codec.includes('truehd') || codec.includes('atmos')) return 'truehd atmos';
    if (audios.some(a => a.label?.toLowerCase().includes('atmos'))) return 'dolby atmos';
    return undefined;
  };

  // Format bitrate
  const formatBitrate = () => {
    if (!tech.bitrate) return null;
    if (tech.bitrate >= 1000) return `${(tech.bitrate / 1000).toFixed(1)} Mbps`;
    return `${tech.bitrate} Kbps`;
  };

  // Format file size
  const formatFileSize = () => {
    if (!tech.fileSize) return null;
    if (tech.fileSize >= 1024) return `${(tech.fileSize / 1024).toFixed(1)} GB`;
    return `${Math.round(tech.fileSize)} MB`;
  };

  // Check for CC/SDH/AD
  const hasCC = subs.some(s => s.label?.toLowerCase().includes('cc') || s.forced);
  const hasSDH = subs.some(s => s.label?.toLowerCase().includes('sdh'));
  const hasAD = audios.some(a => a.label?.toLowerCase().includes('audio desc') || a.label?.toLowerCase().includes('descriptive'));

  const resolution = getResolution();
  const hdr = getHdrFormat();
  const audioChannels = getAudioChannels();
  const audioCodecForBadge = getAudioCodecForBadge();
  const bitrate = formatBitrate();
  const fileSize = formatFileSize();

  return (
    <button
      onClick={onSelect}
      className="w-full flex items-center gap-4 p-4 rounded-xl bg-white/[0.08] hover:bg-white/[0.15] ring-1 ring-white/10 hover:ring-white/30 transition-all duration-150 group text-left"
    >
      {/* Play Icon */}
      <div className="flex-shrink-0 w-10 h-10 rounded-full bg-white/10 group-hover:bg-white/20 flex items-center justify-center transition-colors">
        <svg className="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
          <path d="M8 5v14l11-7z" />
        </svg>
      </div>

      {/* Version Info */}
      <div className="flex-1 min-w-0">
        {/* Label */}
        <p className="text-sm font-semibold text-white mb-1.5">{version.label}</p>

        {/* Tech Badges Row - Using same components as DetailsHero */}
        <div className="flex flex-wrap items-center gap-1.5 mb-2">
          <TechBadgeCompact
            resolution={resolution}
            hdr={hdr}
            audioCodec={audioCodecForBadge}
            size="sm"
          />
          <AccessibilityBadges
            hasCC={hasCC}
            hasSDH={hasSDH}
            hasAD={hasAD}
            size="sm"
          />
        </div>

        {/* Additional Info Row */}
        <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-400">
          {tech.videoCodec && (
            <span className="uppercase">{tech.videoCodec}</span>
          )}
          {audioChannels && (
            <>
              <span className="text-neutral-600">•</span>
              <span>{audioChannels}</span>
            </>
          )}
          {bitrate && (
            <>
              <span className="text-neutral-600">•</span>
              <span>{bitrate}</span>
            </>
          )}
          {fileSize && (
            <>
              <span className="text-neutral-600">•</span>
              <span>{fileSize}</span>
            </>
          )}
          {tech.container && (
            <>
              <span className="text-neutral-600">•</span>
              <span className="uppercase">{tech.container}</span>
            </>
          )}
        </div>
      </div>

      {/* Chevron */}
      <div className="flex-shrink-0">
        <svg className="w-5 h-5 text-neutral-500 group-hover:text-white transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
      </div>
    </button>
  );
}
