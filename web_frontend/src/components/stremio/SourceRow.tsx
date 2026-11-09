import type { ReactNode } from 'react';
import { CopyIcon, OpenOutlineIcon, PlayCircleIcon } from '@/components/ServiceIcons';
import { classifyPlayability, resolutionBucket, type StremioStream } from '@/stremio';

function formatBytes(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(bytes >= 1e10 ? 0 : 1)} GB`;
  return `${Math.round(bytes / 1e6)} MB`;
}

function Badge({ tone = 'neutral', children }: { tone?: 'neutral' | 'good' | 'info'; children: ReactNode }) {
  const tones = {
    neutral: 'bg-white/[0.08] text-[#d1d5db]',
    good: 'bg-[#22c55e]/15 text-[#4ade80]',
    info: 'bg-[#3b82f6]/15 text-[#93c5fd]',
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${tones[tone]}`}>{children}</span>
  );
}

export interface SourceRowProps {
  stream: StremioStream;
  isCurrent?: boolean;
  preparing?: boolean;
  error?: string;
  onPlay: () => void;
  onOpenExternal: () => void;
  onCopyLink: () => void;
  copied?: boolean;
}

/** One source in the sheet. Unplayable sources explain why and offer what still works. */
export default function SourceRow({
  stream,
  isCurrent,
  preparing,
  error,
  onPlay,
  onOpenExternal,
  onCopyLink,
  copied,
}: SourceRowProps) {
  const playability = classifyPlayability(stream);
  const title = stream.title || stream.name || stream.description || 'Unnamed source';
  const resolution = resolutionBucket(stream);
  const qualityLabel = stream.quality?.toUpperCase() || (resolution ? (resolution === 2160 ? '4K' : `${resolution}p`) : null);
  const canOpenExternally = stream.sourceType === 'externalUrl' || stream.sourceType === 'ytId';
  const subtitleCount = stream.subtitles?.length ?? 0;

  const details = (
    <>
      <span className={`block whitespace-pre-line break-words [overflow-wrap:anywhere] text-[14px] font-semibold leading-snug line-clamp-3 ${playability.playable ? 'text-white' : 'text-[#9ca3af]'}`}>
        {title}
      </span>
      <span className="mt-1 block text-[12px] text-[#9ca3af]">{stream.addonName}</span>
      {(qualityLabel || stream.sizeBytes || stream.behaviorHints?.cached || subtitleCount > 0) && (
        <span className="mt-2 flex flex-wrap items-center gap-1.5">
          {qualityLabel && <Badge tone="info">{qualityLabel}</Badge>}
          {stream.sizeBytes ? <Badge>{formatBytes(stream.sizeBytes)}</Badge> : null}
          {stream.behaviorHints?.cached && <Badge tone="good">Cached</Badge>}
          {subtitleCount > 0 && <Badge>{subtitleCount} subs</Badge>}
        </span>
      )}
      {!playability.playable && playability.label && (
        <span className="mt-2 block text-[12px] font-medium text-[#f59e0b]">{playability.label}</span>
      )}
      {error && <span className="mt-2 block text-[12px] font-medium text-[#f87171]">{error}</span>}
    </>
  );

  const surface = `w-full rounded-xl border p-3.5 text-left transition-colors ${
    isCurrent ? 'border-brand/60 bg-white/[0.08]' : playability.playable ? 'border-white/[0.08] bg-white/[0.05]' : 'border-[#f59e0b]/15 bg-white/[0.03]'
  }`;

  if (playability.playable) {
    return (
      <button type="button" onClick={onPlay} disabled={preparing} className={`${surface} flex items-start gap-3 hover:bg-white/[0.09] disabled:opacity-60`}>
        <span className="min-w-0 flex-1">{details}</span>
        <span className="flex-shrink-0 pt-0.5 text-brand">
          {preparing ? (
            <span className="block h-6 w-6 animate-spin rounded-full border-2 border-white/25 border-t-white" aria-label="Preparing" />
          ) : (
            <PlayCircleIcon size={24} />
          )}
        </span>
      </button>
    );
  }

  return (
    <div className={`${surface} flex items-start gap-3`}>
      <div className="min-w-0 flex-1">{details}</div>
      <div className="flex flex-shrink-0 flex-col items-end gap-2">
        {canOpenExternally && (
          <button type="button" onClick={onOpenExternal} className="flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[12px] font-semibold text-white hover:bg-white/20">
            <OpenOutlineIcon size={14} /> Open
          </button>
        )}
        {stream.url && (
          <button type="button" onClick={onCopyLink} className="flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[12px] font-semibold text-white hover:bg-white/20">
            <CopyIcon size={14} /> {copied ? 'Copied' : 'Copy link'}
          </button>
        )}
      </div>
    </div>
  );
}
