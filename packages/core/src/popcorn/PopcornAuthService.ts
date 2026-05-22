/**
 * PopcornAuthService — flow d'authentification custom Popcorn.
 *
 * Remplace le PlexAuthService upstream (PIN polling). Voir
 * docs/popcorn-mobile/ARCHITECTURE.md §3 pour le flow et
 * docs/popcorn-mobile/BACKEND-AUDIT.md §1 pour les endpoints backend.
 *
 * Un seul appel HTTP : POST /api/auth/redeem { code } → token Plex.
 */

import { PopcornConfig } from '../config/PopcornConfig';

export type RedeemResponse = {
  /** Token Plex (~20 chars hex) à utiliser comme X-Plex-Token. */
  token: string;
  /** ID Plex de l'utilisateur Home. */
  plexUserId: string;
  /** UUID Plex (chaîne hex). Optionnel selon la version backend. */
  plexUserUuid?: string;
  /** Username Plex affiché. Optionnel. */
  plexUsername?: string;
  /** Label libre attaché au code (ex: "iPad de Sofiane"). */
  label: string;
};

/** Codes d'erreur backend (cf. handlers.go handleRedeem). */
export type PopcornAuthErrorCode =
  | 'invalid_body'
  | 'invalid_code'
  | 'invalid_format'
  | 'not_found'
  | 'revoked'
  | 'exhausted'
  | 'db_error'
  | 'decrypt_error'
  | 'unknown';

export class PopcornAuthError extends Error {
  constructor(
    public status: number,
    public code: PopcornAuthErrorCode,
    message?: string,
  ) {
    super(message ?? code);
    this.name = 'PopcornAuthError';
  }
}

export class PopcornAuthService {
  constructor(
    private readonly baseUrl: string = PopcornConfig.authBaseUrl,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  /**
   * Échange un code famille contre un token Plex.
   *
   * @throws {PopcornAuthError} sur erreur métier (code invalide, révoqué,
   *   épuisé) ou erreur réseau/serveur.
   */
  async redeemCode(code: string): Promise<RedeemResponse> {
    const trimmed = code.trim();
    if (trimmed.length === 0) {
      throw new PopcornAuthError(400, 'invalid_format', 'Code vide');
    }

    let res: Response;
    try {
      res = await this.fetchImpl(`${this.baseUrl}/api/auth/redeem`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({ code: trimmed }),
      });
    } catch (err) {
      throw new PopcornAuthError(
        0,
        'unknown',
        `Réseau indisponible : ${(err as Error).message}`,
      );
    }

    if (!res.ok) {
      const body = (await res.json().catch(() => ({}))) as {
        code?: string;
        message?: string;
      };
      throw new PopcornAuthError(
        res.status,
        (body.code as PopcornAuthErrorCode) ?? 'unknown',
        body.message,
      );
    }

    const data = (await res.json()) as {
      token: string;
      plex_user_id: string;
      plex_user_uuid?: string;
      plex_username?: string;
      label: string;
    };

    return {
      token: data.token,
      plexUserId: data.plex_user_id,
      plexUserUuid: data.plex_user_uuid,
      plexUsername: data.plex_username,
      label: data.label,
    };
  }
}
