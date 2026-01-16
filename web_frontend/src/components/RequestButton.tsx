import { useState, useEffect, useCallback } from 'react';
import {
  getOverseerrMediaStatus,
  requestMedia,
  OverseerrStatus,
  OverseerrMediaStatus,
} from '@/services/overseerr';
import { loadSettings } from '@/state/settings';
import { OverseerrIcon } from '@/components/ServiceIcons';

type RequestButtonProps = {
  tmdbId: number;
  mediaType: 'movie' | 'tv';
  title?: string;
  className?: string;
  variant?: 'pill' | 'icon' | 'circle';
};

// Status text mapping (matches MacOS buttonLabel)
function getStatusText(status: OverseerrStatus): string {
  const texts: Record<OverseerrStatus, string> = {
    not_requested: 'Request',
    pending: 'Pending',
    approved: 'Approved',
    declined: 'Declined',
    processing: 'Processing',
    partially_available: 'Partial',
    available: 'Available',
    unknown: 'Request',
  };
  return texts[status];
}

// Status colors matching MacOS exactly
// MacOS uses: Indigo #6366F1, Orange, Green, Red, Blue
function getStatusColor(status: OverseerrStatus): string {
  const colors: Record<OverseerrStatus, string> = {
    not_requested: '#6366F1', // Indigo
    pending: '#F97316',       // Orange
    approved: '#22C55E',      // Green
    declined: '#EF4444',      // Red
    processing: '#3B82F6',    // Blue
    partially_available: '#F97316', // Orange
    available: '#22C55E',     // Green
    unknown: '#6366F1',       // Indigo
  };
  return colors[status];
}

// Status icons for non-requestable states (matches MacOS buttonIcon)
function StatusIcon({ status, size = 14 }: { status: OverseerrStatus; size?: number }) {
  switch (status) {
    case 'pending': // clock
      return (
        <svg width={size} height={size} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      );
    case 'approved': // checkmark.circle
    case 'available': // checkmark.circle.fill
      return (
        <svg width={size} height={size} fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
        </svg>
      );
    case 'declined': // xmark.circle
      return (
        <svg width={size} height={size} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      );
    case 'processing': // arrow.clockwise
      return (
        <svg width={size} height={size} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      );
    case 'partially_available': // circle.lefthalf.filled
      return (
        <svg width={size} height={size} fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18V4c4.41 0 8 3.59 8 8s-3.59 8-8 8z" />
        </svg>
      );
    default:
      return null;
  }
}

// Spinner component matching MacOS ProgressView
function Spinner({ size = 18 }: { size?: number }) {
  return (
    <svg className="animate-spin" width={size} height={size} fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      />
    </svg>
  );
}

export default function RequestButton({
  tmdbId,
  mediaType,
  title = '',
  className = '',
  variant = 'pill',
}: RequestButtonProps) {
  const [status, setStatus] = useState<OverseerrMediaStatus | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRequesting, setIsRequesting] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);

  const settings = loadSettings();
  const isEnabled = settings.overseerrEnabled && settings.overseerrUrl && settings.overseerrApiKey;

  const fetchStatus = useCallback(async () => {
    if (!isEnabled) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);

    try {
      const mediaStatus = await getOverseerrMediaStatus(tmdbId, mediaType);
      setStatus(mediaStatus);
    } catch {
      // Failed to fetch status
    } finally {
      setIsLoading(false);
    }
  }, [tmdbId, mediaType, isEnabled]);

  useEffect(() => {
    fetchStatus();
  }, [fetchStatus]);

  const handleRequest = async () => {
    if (!status?.canRequest || isRequesting) return;

    setIsRequesting(true);

    try {
      const result = await requestMedia(tmdbId, mediaType);

      if (result.success) {
        setStatus({
          status: 'pending',
          requestId: result.requestId,
          canRequest: false,
        });
      }
    } catch {
      // Request failed
    } finally {
      setIsRequesting(false);
      setShowConfirm(false);
    }
  };

  const handleClick = () => {
    if (status?.canRequest) {
      setShowConfirm(true);
    }
  };

  // Don't render if Overseerr is not enabled
  if (!isEnabled) return null;

  // Loading state
  if (isLoading) {
    if (variant === 'icon' || variant === 'circle') {
      const size = variant === 'circle' ? 'w-11 h-11' : 'w-8 h-8';
      return <div className={`${size} rounded-full bg-white/10 animate-pulse ${className}`} />;
    }
    // Pill loading - match exact dimensions
    return (
      <div className={`h-[42px] w-[120px] bg-white/10 rounded-lg animate-pulse ${className}`} />
    );
  }

  // No status - hide button
  if (!status) return null;

  // Available items don't need a request button
  if (status.status === 'available') return null;

  const currentStatus = status.status;
  const canRequest = status.canRequest;
  const statusText = getStatusText(currentStatus);
  const statusColor = getStatusColor(currentStatus);
  // MacOS: buttonColor.opacity(canRequest ? 0.9 : 0.4)
  const bgOpacity = canRequest ? 0.9 : 0.4;

  // Confirmation dialog
  const confirmDialog = showConfirm && (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div className="bg-neutral-900 border border-white/10 rounded-2xl p-6 max-w-sm mx-4 shadow-2xl">
        <h3 className="text-white text-lg font-bold mb-2">
          Request {title || 'this title'}?
        </h3>
        <p className="text-neutral-400 text-sm mb-6">
          This will submit a request to Overseerr. You'll be notified when it becomes available.
        </p>
        <div className="flex gap-3">
          <button
            onClick={() => setShowConfirm(false)}
            className="flex-1 px-4 py-2.5 bg-white/10 hover:bg-white/20 text-white font-medium rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleRequest}
            disabled={isRequesting}
            className="flex-1 px-4 py-2.5 text-white font-medium rounded-lg transition-colors disabled:opacity-50"
            style={{ backgroundColor: '#6366F1' }}
          >
            {isRequesting ? 'Requesting...' : 'Request'}
          </button>
        </div>
      </div>
    </div>
  );

  // Icon variant (small) - MacOS iconButton
  // MacOS: 32x32, OverseerrIcon size 20
  if (variant === 'icon') {
    return (
      <>
        {confirmDialog}
        <button
          onClick={handleClick}
          disabled={!canRequest || isRequesting}
          className={`
            w-8 h-8 rounded-full flex items-center justify-center
            transition-all text-white
            ${canRequest ? 'cursor-pointer' : 'cursor-default'}
            ${className}
          `}
          style={{
            backgroundColor: canRequest ? 'transparent' : `${statusColor}${Math.round(bgOpacity * 255).toString(16).padStart(2, '0')}`,
          }}
          title={canRequest ? 'Request via Overseerr' : statusText}
        >
          {isRequesting ? (
            <Spinner size={16} />
          ) : canRequest ? (
            <OverseerrIcon size={20} />
          ) : (
            <StatusIcon status={currentStatus} size={14} />
          )}
        </button>
      </>
    );
  }

  // Circle variant - MacOS style circle button matching the + button
  // Purple gradient background with Overseerr icon
  if (variant === 'circle') {
    return (
      <>
        {confirmDialog}
        <button
          onClick={handleClick}
          disabled={!canRequest || isRequesting}
          className={`
            w-10 h-10 rounded-full flex items-center justify-center
            transition-all text-white
            ${canRequest ? 'cursor-pointer hover:opacity-90' : 'cursor-default opacity-50'}
            ${className}
          `}
          style={{
            background: canRequest
              ? 'linear-gradient(135deg, #C395FC 0%, #4F65F5 100%)'
              : `${statusColor}66`,
          }}
          title={canRequest ? 'Request via Overseerr' : statusText}
        >
          {isRequesting ? (
            <Spinner size={18} />
          ) : canRequest ? (
            <OverseerrIcon size={22} />
          ) : (
            <StatusIcon status={currentStatus} size={18} />
          )}
        </button>
      </>
    );
  }

  // Default pill variant - MacOS pillButton
  // MacOS: HStack spacing 8, icon 18, text 15pt semibold, padding h22 v12, cornerRadius 8
  return (
    <>
      {confirmDialog}
      <button
        onClick={handleClick}
        disabled={!canRequest || isRequesting}
        className={`
          inline-flex items-center justify-center gap-2
          px-[22px] py-3 rounded-lg
          text-[15px] font-semibold text-white
          transition-all
          ${canRequest ? 'cursor-pointer hover:opacity-90' : 'cursor-default'}
          ${className}
        `}
        style={{
          backgroundColor: `${statusColor}${Math.round(bgOpacity * 255).toString(16).padStart(2, '0')}`,
        }}
      >
        {isRequesting ? (
          <Spinner size={18} />
        ) : canRequest ? (
          <OverseerrIcon size={18} />
        ) : (
          <StatusIcon status={currentStatus} size={14} />
        )}
        {statusText}
      </button>
    </>
  );
}
