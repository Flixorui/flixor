import { type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronBackIcon } from '@/components/ServiceIcons';

type SettingsScreenProps = {
  title: string;
  /** Where the back button goes. */
  backTo?: string;
  children: ReactNode;
};

/** Header with a back button and the standard column for a settings page. */
export default function SettingsScreen({ title, backTo = '/settings', children }: SettingsScreenProps) {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen pb-20">
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto flex items-center gap-3">
        <button
          onClick={() => navigate(backTo)}
          aria-label="Back"
          className="-ml-2 flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">{title}</h1>
      </div>
      <div className="px-4 max-w-2xl mx-auto">{children}</div>
    </div>
  );
}
