import { useEffect } from 'react';

export default function Toast({ message, onClose }: { message: string; onClose: () => void }) {
  useEffect(() => { const t = setTimeout(onClose, 4000); return () => clearTimeout(t); }, [onClose]);
  if (!message) return null;
  return (
    <div className="fixed bottom-6 right-6 z-[100] px-4 py-2 rounded-md bg-black/80 text-white shadow ring-1 ring-white/10">
      {message}
    </div>
  );
}
