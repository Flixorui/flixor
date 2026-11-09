export interface LanguageTag {
  base: string;
  variant?: string;
}

const VARIANT_ALIASES: Record<string, LanguageTag> = {
  pob: { base: 'pt', variant: 'br' },
  pb: { base: 'pt', variant: 'br' },
  chs: { base: 'zh', variant: 'hans' },
  zhs: { base: 'zh', variant: 'hans' },
  cht: { base: 'zh', variant: 'hant' },
  zht: { base: 'zh', variant: 'hant' },
};

const BASE_ALIASES: Record<string, string> = {
  alb: 'sq', arm: 'hy', baq: 'eu', bur: 'my', chi: 'zh', cze: 'cs', dut: 'nl', fre: 'fr', geo: 'ka',
  ger: 'de', gre: 'el', ice: 'is', mac: 'mk', mao: 'mi', may: 'ms', per: 'fa', rum: 'ro', slo: 'sk',
  tib: 'bo', wel: 'cy', iw: 'he', in: 'id', ji: 'yi', jp: 'ja', gr: 'el', cn: 'zh', kr: 'ko', scc: 'sr',
  scr: 'hr', nob: 'no', nb: 'no', nno: 'no', nn: 'no', fil: 'tl', cmn: 'zh', yue: 'zh', spa: 'es', por: 'pt',
  eng: 'en', deu: 'de', fra: 'fr', ita: 'it', jpn: 'ja', kor: 'ko', zho: 'zh', rus: 'ru', ara: 'ar',
  hin: 'hi', nld: 'nl', swe: 'sv', nor: 'no', dan: 'da', fin: 'fi', pol: 'pl', tur: 'tr', heb: 'he',
  tha: 'th', vie: 'vi', ind: 'id', ces: 'cs', ell: 'el', hun: 'hu', ron: 'ro', ukr: 'uk', tam: 'ta',
  tel: 'te', ben: 'bn', mal: 'ml', kan: 'kn', mar: 'mr', urd: 'ur',
};

const HOME_VARIANT: Record<string, string> = { pt: 'pt', es: 'es', fr: 'fr', zh: 'hans' };

const LATIN_REGIONS = new Set([
  '419', 'mx', 'ar', 'co', 'cl', 'pe', 've', 'us', 'la', 'lat', 'latam', 'uy', 'py', 'bo', 'ec', 'gt', 'cu',
  'do', 'hn', 'ni', 'pa', 'pr', 'sv', 'cr',
]);

const LANGUAGE_NAMES: Array<[string[], string]> = [
  [['english'], 'en'], [['spanish', 'español', 'espanol', 'castellano', 'latino'], 'es'],
  [['portuguese', 'português', 'portugues'], 'pt'], [['french', 'français', 'francais'], 'fr'],
  [['german', 'deutsch'], 'de'], [['italian', 'italiano'], 'it'], [['japanese', '日本語'], 'ja'],
  [['korean', '한국어'], 'ko'], [['chinese', 'mandarin', 'cantonese', '中文'], 'zh'], [['russian', 'русский'], 'ru'],
  [['arabic', 'العربية'], 'ar'], [['hindi', 'हिन्दी'], 'hi'], [['dutch', 'nederlands'], 'nl'], [['swedish', 'svenska'], 'sv'],
  [['norwegian', 'norsk'], 'no'], [['danish', 'dansk'], 'da'], [['finnish', 'suomi'], 'fi'], [['polish', 'polski'], 'pl'],
  [['turkish', 'türkçe'], 'tr'], [['hebrew', 'עברית'], 'he'], [['thai', 'ไทย'], 'th'], [['vietnamese', 'tiếng việt'], 'vi'],
  [['indonesian'], 'id'], [['czech', 'čeština'], 'cs'], [['greek', 'ελληνικά'], 'el'], [['hungarian', 'magyar'], 'hu'],
  [['romanian', 'română'], 'ro'], [['ukrainian', 'українська'], 'uk'],
];

function normalizeBase(code: string): string | null {
  if (BASE_ALIASES[code]) return BASE_ALIASES[code];
  return /^[a-z]{2,3}$/.test(code) ? code : null;
}

function normalizeVariant(part: string, base: string): string | undefined {
  if (base === 'zh') {
    if (['hans', 'cn', 'sg', 'chs', 'my'].includes(part)) return 'hans';
    if (['hant', 'tw', 'hk', 'mo', 'cht'].includes(part)) return 'hant';
    return undefined;
  }
  if (base === 'pt') {
    if (['br', 'bra'].includes(part)) return 'br';
    if (['pt', 'prt', 'eu'].includes(part)) return 'pt';
    return undefined;
  }
  if (base === 'es') {
    if (LATIN_REGIONS.has(part)) return '419';
    if (['es', 'esp', 'eu'].includes(part)) return 'es';
    return undefined;
  }
  return /^[a-z]{2}$/.test(part) ? part : undefined;
}

/** "pt-BR", "pob", "es-419", "zh-Hant", "chi" to a tag. Null for placeholders such as "und". */
export function parseLanguage(code?: string | null): LanguageTag | null {
  const raw = code?.trim().toLowerCase().replace(/_/g, '-');
  if (!raw || ['und', 'unknown', 'zxx', 'mis', 'mul', 'none', 'n/a'].includes(raw)) return null;
  if (VARIANT_ALIASES[raw]) return VARIANT_ALIASES[raw];
  const [first, ...rest] = raw.split('-');
  const base = normalizeBase(first);
  if (!base) return null;
  for (const part of rest) {
    const variant = normalizeVariant(part, base);
    if (variant) return { base, variant };
  }
  return { base };
}

function hasWord(text: string, word: string): boolean {
  return new RegExp(`(^|[^\\p{L}\\p{N}])${word}([^\\p{L}\\p{N}]|$)`, 'u').test(text);
}

function variantHint(title: string, base: string): string | undefined {
  if (base === 'pt') {
    if (title.includes('brazil') || title.includes('brasil') || hasWord(title, 'br') || title.includes('pt-br')) return 'br';
    if (title.includes('portugal') || title.includes('european') || title.includes('europeu')) return 'pt';
  }
  if (base === 'es') {
    if (title.includes('latin') || title.includes('latam') || hasWord(title, 'lat')) return '419';
    if (title.includes('spain') || title.includes('castellano') || title.includes('españa')) return 'es';
  }
  if (base === 'zh') {
    if (title.includes('simplified') || title.includes('简') || hasWord(title, 'chs')) return 'hans';
    if (title.includes('traditional') || title.includes('繁') || hasWord(title, 'cht')) return 'hant';
  }
  return undefined;
}

export function trackLanguage(lang?: string | null, title?: string | null): LanguageTag | null {
  const titleText = title?.toLowerCase() ?? '';
  let tag = parseLanguage(lang);
  if (!tag && titleText) {
    const named = LANGUAGE_NAMES.find(([names]) => names.some((name) => titleText.includes(name)));
    if (named) tag = { base: named[1] };
  }
  if (!tag) return null;
  if (!tag.variant) {
    const hinted = variantHint(titleText, tag.base);
    if (hinted) return { base: tag.base, variant: hinted };
  }
  return tag;
}

function matchScore(track: LanguageTag, preference: LanguageTag): number | null {
  if (track.base !== preference.base) return null;
  if (preference.variant && track.variant) return preference.variant === track.variant ? 3 : 1;
  if (preference.variant) return 2;
  if (!track.variant) return 3;
  return track.variant === HOME_VARIANT[track.base] ? 3 : 2;
}

/** Best item for `preference`, or null. Forced tracks only win when nothing else matches. */
export function bestLanguageMatch<T>(
  items: T[],
  preference: string,
  describe: (item: T) => { lang?: string | null; title?: string | null; forced?: boolean; isDefault?: boolean },
): T | null {
  const preferred = parseLanguage(preference);
  if (!preferred) return null;
  let best: { item: T; rank: number } | null = null;
  for (const item of items) {
    const { lang, title, forced, isDefault } = describe(item);
    const tag = trackLanguage(lang, title);
    const score = tag ? matchScore(tag, preferred) : null;
    if (score === null) continue;
    const isForced = Boolean(forced) || Boolean(title?.toLowerCase().includes('forced'));
    const rank = score * 4 + (isForced ? 0 : 2) + (isDefault ? 1 : 0);
    if (!best || rank > best.rank) best = { item, rank };
  }
  return best?.item ?? null;
}

export function sameLanguage(a?: string | null, b?: string | null): boolean {
  const left = parseLanguage(a);
  const right = parseLanguage(b);
  return Boolean(left && right && left.base === right.base);
}
