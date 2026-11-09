import { useEffect, useState } from 'react';
import { getInstalledAddons, installAddon } from '@/stremio';

type StepProps = { title: string; subtitle: string; description: string };

export default function AddonSetupStep({ title, subtitle, description }: StepProps) {
  const [url, setUrl] = useState('');
  const [count, setCount] = useState(0);
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getInstalledAddons().then((addons) => setCount(addons.length)).catch(() => {});
  }, []);

  async function install(event: React.FormEvent) {
    event.preventDefault();
    const manifestUrl = url.trim();
    if (!manifestUrl || installing) return;
    setInstalling(true);
    setError(null);
    try {
      await installAddon(manifestUrl);
      setUrl('');
      setCount((n) => n + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not install this addon');
    } finally {
      setInstalling(false);
    }
  }

  return (
    <div className="w-full max-w-lg">
      <h1 className="text-5xl font-extrabold text-white leading-tight whitespace-pre-line mb-4">{title}</h1>
      <h2 className="text-lg font-semibold text-white/60 mb-5">{subtitle}</h2>
      <p className="text-base text-white/40 leading-relaxed max-w-md mb-6">{description}</p>

      <form onSubmit={install} className="flex gap-2">
        <input
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          type="url"
          placeholder="Addon manifest URL"
          aria-label="Addon manifest URL"
          autoComplete="off"
          className="flex-1 min-w-0 px-4 py-3 rounded-xl bg-white/10 border border-white/10 text-sm text-white placeholder:text-white/40 focus:outline-none focus:ring-2 focus:ring-white/20 select-text"
        />
        <button
          type="submit"
          disabled={!url.trim() || installing}
          className="px-5 py-3 rounded-xl bg-white text-black text-sm font-semibold hover:bg-white/90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {installing ? 'Installing...' : 'Install'}
        </button>
      </form>

      {error && (
        <p role="alert" className="mt-3 text-sm text-red-400">
          {error}
        </p>
      )}
      <p className="mt-4 text-sm text-white/60">
        {count === 0 ? 'No addons installed yet' : `${count} addon${count === 1 ? '' : 's'} installed`}
      </p>
    </div>
  );
}
