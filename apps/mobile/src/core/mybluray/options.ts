/**
 * What MyBluray adds to the app, each an on/off choice stored per profile in
 * AppSettings.myblurayOptions. Options know their parent: an option does
 * nothing while its parent is off. Same list and defaults as macOS.
 */
import { getAppSettings } from '../SettingsData';

export type MyBlurayOption =
  | 'appleTrailers' | 'highQualityTrailers' | 'bonusVideos'
  | 'ratings'
  | 'ageRatings' | 'commonSense' | 'imdbGuide' | 'guideDescriptions' | 'revealSpoilers'
  | 'physicalReleases' | 'blurayFormat' | 'uhdFormat' | 'boxSets' | 'quickAdd'
  | 'editionSpecs' | 'editionScores' | 'editionScreenshots' | 'editionArtwork'
  | 'editionDigitalCopy' | 'editionPrice' | 'editionLinks'
  | 'librarySection';

/** Off by default: bonus videos (a larger request per title) and spoilers. */
export function optionDefault(option: MyBlurayOption): boolean {
  return option !== 'bonusVideos' && option !== 'revealSpoilers';
}

export const OPTION_PARENT: Partial<Record<MyBlurayOption, MyBlurayOption>> = {
  highQualityTrailers: 'appleTrailers',
  bonusVideos: 'appleTrailers',
  guideDescriptions: 'imdbGuide',
  revealSpoilers: 'guideDescriptions',
  blurayFormat: 'physicalReleases',
  uhdFormat: 'physicalReleases',
  boxSets: 'physicalReleases',
  quickAdd: 'physicalReleases',
};

export function myblurayKey(settings = getAppSettings()): string {
  return (settings.myblurayApiKey ?? '').trim();
}

/** A key is saved and the master switch is on. */
export function isMyBlurayActive(settings = getAppSettings()): boolean {
  return myblurayKey(settings).length > 0 && settings.myblurayEnabled !== false;
}

/** The stored choice for this option alone. */
export function isChosen(option: MyBlurayOption, settings = getAppSettings()): boolean {
  const stored = settings.myblurayOptions?.[option];
  return stored === undefined ? optionDefault(option) : stored;
}

/** True when an option this one depends on is off. */
export function isBlocked(option: MyBlurayOption, settings = getAppSettings()): boolean {
  let parent = OPTION_PARENT[option];
  while (parent) {
    if (!isChosen(parent, settings)) return true;
    parent = OPTION_PARENT[parent];
  }
  return false;
}

/** Whether a screen should show this: MyBluray is on, and so are the option and its parents. */
export function isMyBlurayOn(option: MyBlurayOption, settings = getAppSettings()): boolean {
  return isMyBlurayActive(settings) && isChosen(option, settings) && !isBlocked(option, settings);
}

/** Markets Blu-ray.com covers well, for the country picker. */
export const DISC_COUNTRIES: { code: string; name: string }[] = [
  { code: 'US', name: 'United States' }, { code: 'GB', name: 'United Kingdom' }, { code: 'CA', name: 'Canada' },
  { code: 'AU', name: 'Australia' }, { code: 'DE', name: 'Germany' }, { code: 'FR', name: 'France' },
  { code: 'IT', name: 'Italy' }, { code: 'ES', name: 'Spain' }, { code: 'NL', name: 'Netherlands' },
  { code: 'SE', name: 'Sweden' }, { code: 'NO', name: 'Norway' }, { code: 'DK', name: 'Denmark' },
  { code: 'FI', name: 'Finland' }, { code: 'PL', name: 'Poland' }, { code: 'JP', name: 'Japan' },
  { code: 'KR', name: 'South Korea' }, { code: 'HK', name: 'Hong Kong' }, { code: 'TW', name: 'Taiwan' },
  { code: 'CN', name: 'China' }, { code: 'IN', name: 'India' }, { code: 'BR', name: 'Brazil' },
  { code: 'MX', name: 'Mexico' }, { code: 'NZ', name: 'New Zealand' },
];

/** The device's region when Blu-ray.com lists it; otherwise the US. */
export function localRegion(): string {
  let region = 'US';
  try {
    const locale = Intl.DateTimeFormat().resolvedOptions().locale || '';
    const match = /[-_]([A-Z]{2})\b/.exec(locale);
    if (match) region = match[1];
  } catch {
    // Older engines: keep US.
  }
  return DISC_COUNTRIES.some((c) => c.code === region) ? region : 'US';
}

/** The market to ask for disc releases, or undefined for every market. */
export function effectiveDiscCountry(settings = getAppSettings()): string | undefined {
  const value = settings.myblurayDiscCountry || 'auto';
  if (value === 'all') return undefined;
  if (value === 'auto') return localRegion();
  return value;
}

export function countryName(code?: string | null): string {
  if (!code) return '';
  return DISC_COUNTRIES.find((c) => c.code === code)?.name ?? code;
}
