/**
 * Configuration centralisée Popcorn Mobile.
 *
 * Tout ce qui diverge de Flixor upstream passe par ce fichier (URLs, defaults,
 * branding). Référence : docs/popcorn-mobile/ARCHITECTURE.md §5.
 *
 * Ne pas importer depuis le code mobile en dur — utiliser via
 * @popcorn/core / @flixor/core selon le renaming choisi.
 */

export const PopcornConfig = {
  /** Backend d'auth custom (flow redeem-code). Voir BACKEND-AUDIT.md. */
  authBaseUrl: 'https://auth.thepopcorn.fr',

  /** Serveur Plex pré-rempli — pas de picker côté utilisateur. */
  defaultServerUrl: 'https://thepopcorn.fr',

  /** Nom envoyé dans X-Plex-Product. */
  productName: 'Popcorn',

  /** Langues par défaut pour piste audio et sous-titres. */
  defaultAudioLang: 'fr',
  defaultSubtitleLang: 'fr',

  /** Couleur primaire UI (héritée Flixor, identique). */
  brandColor: '#E50914',

  /** Endpoint OTA self-host sur NAS UGREEN. */
  updatesUrl: 'https://ota.thepopcorn.fr/api/manifest',
} as const;

export type PopcornConfigShape = typeof PopcornConfig;
