import { useEffect, useRef } from 'react';
import { useOnlineStatus } from '@/hooks/useOnlineStatus';
import { showToast } from '@/services/toast';

/** Shows a pill while offline, and a toast when the connection comes back. */
export default function NetworkStatusBanner() {
  const online = useOnlineStatus();
  const wasOnline = useRef(online);

  useEffect(() => {
    if (online && !wasOnline.current) showToast('Back online', 'success');
    wasOnline.current = online;
  }, [online]);

  if (online) return null;
  return (
    <div role="status" className="fixed top-[68px] left-1/2 -translate-x-1/2 z-[60] pointer-events-none">
      <div className="px-4 py-1.5 rounded-full bg-amber-500/90 text-black text-[13px] font-semibold shadow-lg whitespace-nowrap">
        You're offline. Some content may not load.
      </div>
    </div>
  );
}
