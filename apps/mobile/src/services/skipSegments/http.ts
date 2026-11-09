/**
 * HTTP helper for the community skip-segment clients: short timeouts and 429 handling.
 * macOS reference: Services/SkipSegments/SkipSegmentHTTP.swift
 */

import { Platform } from 'react-native';

const REQUEST_TIMEOUT_MS = 8_000;

export class RateLimitedError extends Error {
  constructor(readonly retryAfterMs: number | null) {
    super('Rate limited');
  }
}

async function retryAfterMs(response: Response): Promise<number | null> {
  const header = Number(response.headers.get('retry-after'));
  if (Number.isFinite(header) && header > 0) {
    return header * 1000;
  }
  try {
    const reset = (await response.json())?.reset_at;
    if (typeof reset === 'number') {
      return reset > 1_000_000_000 ? reset * 1000 - Date.now() : reset * 1000;
    }
    if (typeof reset === 'string') {
      const at = Date.parse(reset);
      return Number.isNaN(at) ? null : at - Date.now();
    }
  } catch {
    // No usable body; the caller falls back to its default back-off.
  }
  return null;
}

async function send(url: string, init: RequestInit): Promise<any> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      ...init,
      headers: {
        Accept: 'application/json',
        'User-Agent': `Flixor (${Platform.OS})`,
        ...(init.headers as Record<string, string> | undefined),
      },
      signal: controller.signal,
    });
    if (response.status === 429) {
      throw new RateLimitedError(await retryAfterMs(response));
    }
    // Most providers answer "unknown title" with 404.
    if (response.status === 404) {
      return null;
    }
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  } finally {
    clearTimeout(timer);
  }
}

export function getJson(url: string): Promise<any> {
  return send(url, { method: 'GET' });
}

export function postJson(url: string, body: unknown, headers?: Record<string, string>): Promise<any> {
  return send(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

/** Number from a JSON value: numbers, numeric strings, or clock strings (mm:ss, hh:mm:ss). */
export function parseSeconds(raw: unknown): number | null {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? raw : null;
  }
  if (typeof raw !== 'string') {
    return null;
  }
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const direct = Number(trimmed);
  if (Number.isFinite(direct)) return direct;
  const parts = trimmed.split(':').map(Number);
  if (parts.length > 3 || parts.some((part) => !Number.isFinite(part))) return null;
  return parts.reduce((total, part) => total * 60 + part, 0);
}

export function parseString(raw: unknown): string | null {
  if (typeof raw === 'string') return raw || null;
  if (typeof raw === 'number') return String(raw);
  return null;
}

export function parseInteger(raw: unknown): number | null {
  if (typeof raw === 'number') return Math.trunc(raw);
  if (typeof raw === 'string' && /^-?\d+$/.test(raw)) return Number(raw);
  return null;
}
