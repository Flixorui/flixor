export default function Pill({ children, active, onClick }: { children: React.ReactNode; active?: boolean; onClick?: () => void }) {
  return (
    <button onClick={onClick} className={`h-8 px-3 rounded-full text-sm ring-1 transition-colors ${active ? 'bg-white text-black ring-white/0' : 'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}>
      {children}
    </button>
  );
}

