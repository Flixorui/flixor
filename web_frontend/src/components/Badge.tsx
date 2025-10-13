export default function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center h-6 px-2 rounded-md bg-white/10 text-white text-xs font-medium ring-1 ring-white/10">
      {children}
    </span>
  );
}

