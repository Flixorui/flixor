import { useNavigate } from 'react-router-dom';

interface Props {
  message: string;
  action?: { label: string; to: string };
}

/** Full-screen error for a player route that has nothing to play. */
export default function PlayerErrorScreen({ message, action }: Props) {
  const nav = useNavigate();
  return (
    <div className="fixed inset-0 z-50 bg-black flex items-center justify-center p-6">
      <div className="text-white text-center max-w-lg">
        <div className="mb-6 text-lg">{message}</div>
        <div className="flex flex-wrap gap-2 justify-center">
          {action && (
            <button className="px-4 py-2 bg-brand hover:bg-brand-600 rounded" onClick={() => nav(action.to, { replace: true })}>
              {action.label}
            </button>
          )}
          <button className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded" onClick={() => nav(-1)}>Go back</button>
        </div>
      </div>
    </div>
  );
}
