import { useCallback, useEffect, useState } from 'react';
import SettingsCard from '@/components/SettingsCard';
import { ChevronDownIcon, CloseCircleIcon, OpenOutlineIcon } from '@/components/ServiceIcons';
import {
  getInstalledAddons,
  installAddon,
  removeAddon,
  reorderAddons,
  subscribeAddons,
  type StremioAddon,
} from '@/stremio';

/** Host only: the rest of a manifest URL can hold debrid keys. */
function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
}

function capabilities(addon: StremioAddon): string {
  const labels: string[] = [];
  if (addon.resources.includes('stream')) labels.push('Streams');
  if (addon.resources.includes('subtitles')) labels.push('Subtitles');
  if (addon.catalogs.length > 0) labels.push('Catalogs');
  if (addon.resources.includes('meta')) labels.push('Details');
  return labels.join(' • ') || 'No supported features';
}

function AddonLogo({ addon }: { addon: StremioAddon }) {
  const [failed, setFailed] = useState(false);
  if (addon.logo && !failed) {
    return <img src={addon.logo} alt="" onError={() => setFailed(true)} className="h-10 w-10 rounded-[10px] bg-white/10 object-contain" />;
  }
  return (
    <div className="flex h-10 w-10 items-center justify-center rounded-[10px] bg-white/10 text-[15px] font-bold text-white">
      {addon.name.slice(0, 1).toUpperCase()}
    </div>
  );
}

const iconButton = 'flex h-8 w-8 items-center justify-center rounded-full text-[#d1d5db] hover:bg-white/10 disabled:opacity-30 disabled:hover:bg-transparent';

/** Install, reorder, configure and remove addons. */
export default function StremioAddons() {
  const [addons, setAddons] = useState<StremioAddon[]>([]);
  const [loading, setLoading] = useState(true);
  const [manifestUrl, setManifestUrl] = useState('');
  const [installing, setInstalling] = useState(false);
  const [installError, setInstallError] = useState<string | null>(null);
  const [confirmRemoveId, setConfirmRemoveId] = useState<string | null>(null);

  const refresh = useCallback(() => {
    getInstalledAddons().then(setAddons).finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    refresh();
    return subscribeAddons(refresh);
  }, [refresh]);

  const install = async () => {
    setInstalling(true);
    setInstallError(null);
    try {
      await installAddon(manifestUrl);
      setManifestUrl('');
    } catch (err: any) {
      setInstallError(err?.message || 'The addon could not be installed');
    } finally {
      setInstalling(false);
    }
  };

  const move = (index: number, delta: number) => {
    const ids = addons.map((addon) => addon.installationId);
    [ids[index], ids[index + delta]] = [ids[index + delta], ids[index]];
    reorderAddons(ids);
  };

  return (
    <>
      <SettingsCard title="Install">
        <form
          className="flex flex-col gap-2 p-[14px] sm:flex-row"
          onSubmit={(event) => {
            event.preventDefault();
            if (!installing && manifestUrl.trim()) install();
          }}
        >
          <input
            value={manifestUrl}
            onChange={(event) => setManifestUrl(event.target.value)}
            placeholder="https://example.com/manifest.json"
            aria-label="Addon manifest URL"
            spellCheck={false}
            autoComplete="off"
            className="min-w-0 flex-1 rounded-lg bg-white/[0.08] px-3 py-2 text-[14px] text-white placeholder:text-[#6b7280] focus:outline-none focus:ring-2 focus:ring-brand/60"
          />
          <button
            type="submit"
            disabled={installing || !manifestUrl.trim()}
            className="rounded-lg bg-brand px-4 py-2 text-[14px] font-semibold text-white disabled:opacity-50"
          >
            {installing ? 'Installing…' : 'Install'}
          </button>
        </form>
        {installError && <p className="px-[14px] pb-[14px] text-[13px] text-[#f87171]">{installError}</p>}
      </SettingsCard>

      <SettingsCard title="Installed">
        {loading ? (
          <p className="px-[14px] py-8 text-center text-[13px] text-[#9ca3af]">Loading…</p>
        ) : addons.length === 0 ? (
          <p className="px-[14px] py-8 text-center text-[13px] text-[#9ca3af]">No addons installed. Paste a manifest URL above to add one.</p>
        ) : (
          addons.map((addon, index) => (
            <div key={addon.installationId} className={`flex items-center gap-3 px-[14px] py-3 ${index < addons.length - 1 ? 'border-b border-white/[0.08]' : ''}`}>
              <AddonLogo addon={addon} />
              <div className="min-w-0 flex-1">
                <span className="block truncate text-[15px] font-semibold text-[#f9fafb]">{addon.name}</span>
                <span className="block truncate text-[12px] text-[#9ca3af]">{capabilities(addon)}{addon.version ? ` • v${addon.version}` : ''}</span>
                <span className="block truncate text-[11px] text-[#6b7280]">{hostOf(addon.manifestUrl)}</span>
              </div>
              <div className="flex flex-shrink-0 items-center">
                <button type="button" onClick={() => move(index, -1)} disabled={index === 0} aria-label={`Move ${addon.name} up`} className={iconButton}>
                  <span className="rotate-180"><ChevronDownIcon size={18} /></span>
                </button>
                <button type="button" onClick={() => move(index, 1)} disabled={index === addons.length - 1} aria-label={`Move ${addon.name} down`} className={iconButton}>
                  <ChevronDownIcon size={18} />
                </button>
                {addon.configureUrl && (
                  <a href={addon.configureUrl} target="_blank" rel="noreferrer noopener" aria-label={`Configure ${addon.name}`} className={iconButton}>
                    <OpenOutlineIcon size={16} />
                  </a>
                )}
                {confirmRemoveId === addon.installationId ? (
                  <button type="button" onClick={() => { removeAddon(addon.installationId); setConfirmRemoveId(null); }} className="ml-1 rounded-full bg-[#ef4444]/20 px-3 py-1 text-[12px] font-semibold text-[#f87171]">
                    Remove
                  </button>
                ) : (
                  <button type="button" onClick={() => setConfirmRemoveId(addon.installationId)} aria-label={`Remove ${addon.name}`} className={iconButton}>
                    <CloseCircleIcon size={18} />
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </SettingsCard>

      <p className="px-1 text-[12px] leading-relaxed text-[#9ca3af]">
        Sources are tried in this order. Addon links stay in this browser. Flixor only sends one to its server when the browser can't reach the addon directly.
      </p>
    </>
  );
}
