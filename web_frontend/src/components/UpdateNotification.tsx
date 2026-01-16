import { useState, useEffect, useCallback } from 'react';
import { UpdateInfo, checkForUpdate, isUpdateDismissed, dismissUpdate } from '@/services/versionCheck';

// Global state to track if we've already checked this session
let hasCheckedThisSession = false;

export default function UpdateNotification() {
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [isVisible, setIsVisible] = useState(false);

  const performCheck = useCallback(async () => {
    const info = await checkForUpdate();
    if (info.hasUpdate && !isUpdateDismissed(info.latestVersion)) {
      setUpdateInfo(info);
      setIsVisible(true);
    }
  }, []);

  // Check on mount (triggered when Home page loads)
  useEffect(() => {
    // Only check once per session to avoid repeated checks
    if (!hasCheckedThisSession) {
      hasCheckedThisSession = true;
      performCheck();
    }
  }, [performCheck]);

  const handleDismiss = () => {
    if (updateInfo) {
      dismissUpdate(updateInfo.latestVersion);
    }
    setIsVisible(false);
  };

  if (!isVisible || !updateInfo) {
    return null;
  }

  return (
    <div className="fixed bottom-4 right-4 z-50 max-w-sm animate-in slide-in-from-bottom-4 fade-in duration-300">
      <div className="bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl p-4">
        <div className="flex items-start gap-3">
          {/* Update icon */}
          <div className="flex-shrink-0 w-10 h-10 bg-blue-500/20 rounded-full flex items-center justify-center">
            <svg className="w-5 h-5 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </div>

          <div className="flex-1 min-w-0">
            <h3 className="text-white font-medium text-sm">Update Available</h3>
            <p className="text-zinc-400 text-xs mt-1">
              Flixor <span className="text-blue-400 font-mono">v{updateInfo.latestVersion}</span> is available
              <span className="text-zinc-500"> (you have v{updateInfo.currentVersion})</span>
            </p>

            {updateInfo.releaseNotes && (
              <p className="text-zinc-500 text-xs mt-2 line-clamp-2">
                {updateInfo.releaseNotes}
              </p>
            )}

            <div className="flex items-center gap-2 mt-3">
              {updateInfo.releaseUrl && (
                <a
                  href={updateInfo.releaseUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white text-xs font-medium rounded transition-colors"
                >
                  View Release
                </a>
              )}
              <button
                onClick={handleDismiss}
                className="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-xs font-medium rounded transition-colors"
              >
                Dismiss
              </button>
            </div>

            <p className="text-zinc-600 text-xs mt-3">
              Run <code className="bg-zinc-800 px-1 py-0.5 rounded text-zinc-400">docker pull</code> to update
            </p>
          </div>

          {/* Close button */}
          <button
            onClick={handleDismiss}
            className="flex-shrink-0 text-zinc-500 hover:text-zinc-300 transition-colors"
            aria-label="Dismiss"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
