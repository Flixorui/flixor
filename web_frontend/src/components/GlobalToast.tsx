import { useEffect, useState } from 'react';

export default function GlobalToast() {
  const [msg, setMsg] = useState<string>('');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const onToast = (e: Event) => {
      const ce = e as CustomEvent<any>;
      const text = typeof ce.detail === 'string' ? ce.detail : (ce.detail?.message || '');
      if (!text) return;
      setMsg(text);
      setVisible(true);
      window.clearTimeout((onToast as any)._t);
      (onToast as any)._t = window.setTimeout(() => setVisible(false), 2500);
    };
    window.addEventListener('app-toast', onToast as any);
    return () => window.removeEventListener('app-toast', onToast as any);
  }, []);

  if (!visible) return null;
  return (
    <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-[1000]">
      <div className="px-4 py-2 rounded-full bg-black/80 text-white text-sm ring-1 ring-white/10 shadow-lg">
        {msg}
      </div>
    </div>
  );
}

