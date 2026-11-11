/**
 * HTTP clients for Streaming Availability (api.movieofthenight.com/v4) and a FlixPatrol JSON
 * API (v2). Both take the key in X-API-Key; keys never go into logs.
 * macOS reference: StreamingAvailabilityClient.swift
 */

import type { SAQuota } from './Top10Models';
import type { FlixPatrolSource } from './Top10Secrets';

export const SA_BASE = 'https://api.movieofthenight.com/v4';

export class Top10HttpError extends Error {
  constructor(public status: number, public source: 'sa' | 'fp', detail?: string) {
    super(Top10HttpError.describe(status, source, detail));
  }

  static describe(status: number, source: 'sa' | 'fp', detail?: string): string {
    if (source === 'fp') {
      if (status === 401 || status === 403) return "FlixPatrol didn't accept the API key.";
      if (status === 404) return detail || 'FlixPatrol has no data for that (404).';
      return detail || `FlixPatrol returned an error (${status}).`;
    }
    if (status === 401 || status === 403) return 'The API key was not accepted.';
    if (status === 429) return 'The monthly call quota is used up.';
    return detail || `The service returned an error (${status}).`;
  }
}

export const OVER_BUDGET = "Today's call limit is used up. Showing saved lists.";

function queryString(query: Record<string, string>): string {
  const parts = Object.entries(query).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  return parts.length ? `?${parts.join('&')}` : '';
}

async function request(url: string, key: string): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    return await fetch(url, { headers: { 'X-API-Key': key, Accept: 'application/json' }, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function errorDetail(res: Response, field: 'message' | 'detail'): Promise<string | undefined> {
  try {
    const body = await res.json();
    return typeof body?.[field] === 'string' ? body[field] : undefined;
  } catch {
    return undefined;
  }
}

function quotaFrom(res: Response): SAQuota | null {
  const used = Number(res.headers.get('x-quota-used'));
  const granted = Number(res.headers.get('x-quota-granted'));
  if (!res.headers.get('x-quota-used') || Number.isNaN(used) || Number.isNaN(granted)) return null;
  const reset = res.headers.get('x-quota-reset');
  const resetsAt = reset ? Date.parse(reset) : NaN;
  return { used, granted, resetsAt: Number.isNaN(resetsAt) ? undefined : resetsAt, observedAt: Date.now() };
}

/** GET from Streaming Availability; the body text and the quota it reported. */
export async function saGet(key: string, path: string, query: Record<string, string> = {}): Promise<{ body: string; quota: SAQuota | null }> {
  const res = await request(`${SA_BASE}/${path}${queryString(query)}`, key);
  const quota = quotaFrom(res);
  if (!res.ok) {
    console.warn(`[StreamingAvailability] HTTP ${res.status} for ${path}`);
    throw new Top10HttpError(res.status, 'sa', await errorDetail(res, 'message'));
  }
  return { body: await res.text(), quota };
}

/** GET from a FlixPatrol source; the body text. */
export async function fpGet(source: FlixPatrolSource, path: string, query: Record<string, string> = {}): Promise<string> {
  if (!/^https?:\/\/[^/]+/i.test(source.url)) throw new Error("That isn't a valid URL.");
  const res = await request(`${source.url}/${path}${queryString(query)}`, source.key);
  if (!res.ok) {
    console.warn(`[FlixPatrol] HTTP ${res.status} for ${path}`);
    throw new Top10HttpError(res.status, 'fp', await errorDetail(res, 'detail'));
  }
  return res.text();
}
