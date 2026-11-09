/**
 * Opaque tokens for the addon media proxy. A token is issued only for a URL an addon
 * returned to this server, and it is bound to the user who asked for it.
 *
 * Tokens are encrypted, not just signed: they travel in URLs, which end up in access
 * logs, and stream URLs often embed debrid keys.
 */
import crypto from 'crypto';
import { AppError } from '../../middleware/errorHandler';

export interface StreamTokenPayload {
  /** Upstream URL. */
  url: string;
  /** Request headers the addon asked for (`behaviorHints.proxyHeaders.request`). */
  headers?: Record<string, string>;
}

interface SealedPayload extends StreamTokenPayload {
  userId: string;
  expiresAt: number;
}

/** Long enough for a film, with room for pausing. */
const TOKEN_TTL_MS = 12 * 60 * 60 * 1000;
const IV_BYTES = 12;
const TAG_BYTES = 16;

let cachedKey: Buffer | undefined;

function tokenKey(): Buffer {
  // Hashed rather than scrypt-derived: a long HLS playlist mints thousands of tokens.
  cachedKey ??= crypto
    .createHash('sha256')
    .update(`flixor.stremio.stream-token:${process.env.SESSION_SECRET || 'change-this-in-production'}`)
    .digest();
  return cachedKey;
}

export function sealStreamToken(payload: StreamTokenPayload, userId: string): string {
  const sealed: SealedPayload = { ...payload, userId, expiresAt: Date.now() + TOKEN_TTL_MS };
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv('aes-256-gcm', tokenKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(sealed), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url');
}

export function openStreamToken(token: string, userId: string): StreamTokenPayload {
  const invalid = () => new AppError('This stream link is no longer valid', 403);
  let sealed: SealedPayload;
  try {
    const raw = Buffer.from(token, 'base64url');
    const decipher = crypto.createDecipheriv('aes-256-gcm', tokenKey(), raw.subarray(0, IV_BYTES));
    decipher.setAuthTag(raw.subarray(IV_BYTES, IV_BYTES + TAG_BYTES));
    const plaintext = Buffer.concat([
      decipher.update(raw.subarray(IV_BYTES + TAG_BYTES)),
      decipher.final(),
    ]);
    sealed = JSON.parse(plaintext.toString('utf8'));
  } catch {
    throw invalid();
  }
  if (sealed.userId !== userId || sealed.expiresAt < Date.now()) throw invalid();
  return { url: sealed.url, headers: sealed.headers };
}
