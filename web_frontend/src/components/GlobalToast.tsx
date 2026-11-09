import { useEffect, useRef, useState } from 'react';
import { CheckmarkCircleIcon, CloseCircleIcon, InformationCircleIcon } from '@/components/ServiceIcons';
import type { ToastDetail, ToastType } from '@/services/toast';

const DEFAULT_DURATION = 3000;

const ICONS: Record<ToastType, JSX.Element> = {
  success: <CheckmarkCircleIcon size={20} color="#22c55e" />,
  error: <CloseCircleIcon size={20} color="#ef4444" />,
  info: <InformationCircleIcon size={20} color="#60a5fa" />,
};

/**
 * App-wide toast. Listens for the `app-toast` window event, whose detail is either
 * a plain string or a {@link ToastDetail}. Use showToast() from services/toast.
 */
export default function GlobalToast() {
  const [toast, setToast] = useState<(ToastDetail & { type: ToastType }) | null>(null);
  const timer = useRef<number>();

  useEffect(() => {
    const onToast = (event: Event) => {
      const detail = (event as CustomEvent<string | ToastDetail>).detail;
      const next = typeof detail === 'string' ? { message: detail } : detail;
      if (!next?.message) return;
      setToast({ ...next, type: next.type ?? 'info' });
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => setToast(null), next.duration ?? DEFAULT_DURATION);
    };
    window.addEventListener('app-toast', onToast);
    return () => {
      window.removeEventListener('app-toast', onToast);
      window.clearTimeout(timer.current);
    };
  }, []);

  if (!toast) return null;
  return (
    <div
      role={toast.type === 'error' ? 'alert' : 'status'}
      className="fixed left-1/2 -translate-x-1/2 bottom-20 md:bottom-6 z-[1000] w-[min(26rem,calc(100vw-2rem))]"
    >
      <div className="flex items-center gap-3 pl-3.5 pr-2.5 py-2.5 rounded-xl bg-black/90 text-white text-sm ring-1 ring-white/10 shadow-lg backdrop-blur-md">
        <span className="flex-shrink-0">{ICONS[toast.type]}</span>
        <span className="flex-1 min-w-0 break-words">{toast.message}</span>
        <button
          type="button"
          aria-label="Dismiss"
          onClick={() => setToast(null)}
          className="flex-shrink-0 w-6 h-6 rounded-full text-white/60 hover:text-white hover:bg-white/10 transition-colors"
        >
          &times;
        </button>
      </div>
    </div>
  );
}
