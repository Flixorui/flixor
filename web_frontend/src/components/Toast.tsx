import { useEffect, useRef } from 'react';
import { showToast } from '@/services/toast';

/** Per-page toast. Shows through the app-wide toast so every message looks the same. */
export default function Toast({ message, onClose }: { message: string; onClose: () => void }) {
  const close = useRef(onClose);
  close.current = onClose;

  useEffect(() => {
    if (!message) return;
    showToast(message);
    const t = setTimeout(() => close.current(), 3000);
    return () => clearTimeout(t);
  }, [message]);

  return null;
}
