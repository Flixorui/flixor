import { useNavigate } from 'react-router-dom';
import SettingsCard from '@/components/SettingsCard';
import { ChevronBackIcon } from '@/components/ServiceIcons';

type StubPageProps = {
  title: string;
  message: string;
  /** Where the back button goes. Defaults to the previous history entry. */
  backTo?: string;
};

/** Header and empty state for a routed page whose content has not been built yet. */
export default function StubPage({ title, message, backTo }: StubPageProps) {
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      <div className="px-4 pt-6 pb-4 flex items-center gap-3">
        <button
          onClick={() => (backTo ? navigate(backTo) : navigate(-1))}
          aria-label="Back"
          className="flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">{title}</h1>
      </div>
      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard>
          <p className="px-[14px] py-8 text-center text-[#9ca3af] text-[13px]">{message}</p>
        </SettingsCard>
      </div>
    </div>
  );
}
