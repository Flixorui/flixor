/**
 * Hard limits on Streaming Availability calls, per key: a daily cap counted on this phone
 * and a monthly floor from the quota the API reports. With several keys, each request goes
 * to the key with the most calls left, so more keys means more calls. Counters are kept by
 * key fingerprint, never by key.
 * macOS reference: StreamingAvailabilityBudget.swift
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { SAQuota } from './Top10Models';
import { quotaRemaining } from './Top10Models';

/** A key stops being used once its month has this few calls left. */
export const MONTHLY_RESERVE = 10;
export const DAILY_LIMIT_CHOICES = [10, 15, 20, 25, 30];

type State = {
  day: string;
  month: string;
  dayCounts: Record<string, number>;
  monthCounts: Record<string, number>;
  quotas: Record<string, SAQuota>;
  dailyLimit: number;
};

const STORAGE = 'streamingAvailability.budget';
let state: State = { day: '', month: '', dayCounts: {}, monthCounts: {}, quotas: {}, dailyLimit: 25 };
let loaded = false;

const pad = (n: number) => String(n).padStart(2, '0');
function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}
function thisMonthUTC(): string {
  const d = new Date();
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}`;
}
function nextMonthStartUTC(): number {
  const d = new Date();
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1);
}

async function persist() {
  try {
    await AsyncStorage.setItem(STORAGE, JSON.stringify(state));
  } catch {
    // counts stay in memory for this session
  }
}

export async function loadBudget(): Promise<void> {
  if (loaded) return;
  loaded = true;
  try {
    const raw = await AsyncStorage.getItem(STORAGE);
    if (raw) state = { ...state, ...JSON.parse(raw) };
  } catch {
    // start fresh
  }
  state.dailyLimit = Math.min(40, Math.max(5, state.dailyLimit || 25));
  rollOver();
}

/** Clears the counters when the day or month changed. */
function rollOver() {
  if (state.day !== today()) {
    state.day = today();
    state.dayCounts = {};
  }
  if (state.month !== thisMonthUTC()) {
    state.month = thisMonthUTC();
    state.monthCounts = {};
  }
}

export const dailyLimit = () => state.dailyLimit;
export async function setDailyLimit(limit: number) {
  state.dailyLimit = limit;
  await persist();
}

export function callsToday(fp: string): number {
  return state.day === today() ? state.dayCounts[fp] ?? 0 : 0;
}

export function callsThisMonth(fp: string): number {
  return state.month === thisMonthUTC() ? state.monthCounts[fp] ?? 0 : 0;
}

export const quotaFor = (fp: string): SAQuota | undefined => state.quotas[fp];

/** Calls left today for one key, after both limits. */
export function allowance(fp: string): number {
  const daily = Math.max(0, state.dailyLimit - callsToday(fp));
  const quota = state.quotas[fp];
  if (!quota || (quota.resetsAt && quota.resetsAt <= Date.now())) return daily;
  return Math.min(daily, Math.max(0, quotaRemaining(quota) - MONTHLY_RESERVE));
}

export const totalAllowance = (fps: string[]) => fps.reduce((n, fp) => n + allowance(fp), 0);
export const totalCallsToday = (fps: string[]) => fps.reduce((n, fp) => n + callsToday(fp), 0);

/** Reserves one call on the key with the most calls left; null means no request may be made. */
export function spend(fps: string[]): string | null {
  rollOver();
  let best: string | null = null;
  for (const fp of fps) if (best === null || allowance(fp) > allowance(best)) best = fp;
  if (best === null || allowance(best) <= 0) return null;
  state.dayCounts[best] = (state.dayCounts[best] ?? 0) + 1;
  state.monthCounts[best] = (state.monthCounts[best] ?? 0) + 1;
  persist();
  return best;
}

export function recordQuota(fp: string, quota: SAQuota | null) {
  if (!quota) return;
  state.quotas[fp] = quota;
  persist();
}

/** HTTP 429: the key's month is used up; leave it alone until the reset. */
export function markExhausted(fp: string) {
  const old = state.quotas[fp];
  const granted = old?.granted ?? 1000;
  state.quotas[fp] = { used: granted, granted, resetsAt: old?.resetsAt ?? nextMonthStartUTC(), observedAt: Date.now() };
  persist();
}

export function forgetKey(fp: string) {
  delete state.dayCounts[fp];
  delete state.monthCounts[fp];
  delete state.quotas[fp];
  persist();
}
