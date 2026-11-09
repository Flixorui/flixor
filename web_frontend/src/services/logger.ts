import { getSettings, subscribeSettings } from '@/state/settings';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export type LogEntry = {
  id: number;
  timestamp: number;
  level: LogLevel;
  message: string;
};

const MAX_ENTRIES = 500;

// Keeps the key so the log still shows what was hidden.
const SENSITIVE_PATTERNS = [
  /((?:x-plex-)?token["'\s:=]+)[\w.~%-]+/gi,
  /(password["'\s:=]+)[^\s"'&,]+/gi,
  /(api[_-]?key["'\s:=]+)[\w.~%-]+/gi,
  /(secret["'\s:=]+)[\w.~%-]+/gi,
  /(authorization["'\s:=]+)[^"'\n,]+/gi,
  /(bearer\s+)[\w.~%-]+/gi,
  /(\bpin["'\s:=]+)\d+/gi,
];

function redact(text: string): string {
  return SENSITIVE_PATTERNS.reduce((out, pattern) => out.replace(pattern, '$1[REDACTED]'), text);
}

function stringify(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value instanceof Error) return value.stack || value.message;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

let entries: LogEntry[] = [];
let nextId = 1;
const listeners = new Set<() => void>();

function addEntry(level: LogLevel, args: unknown[]) {
  const message = redact(args.map(stringify).join(' '));
  const entry = { id: nextId++, timestamp: Date.now(), level, message };
  entries = entries.length >= MAX_ENTRIES ? [...entries.slice(1), entry] : [...entries, entry];
  listeners.forEach((listener) => listener());
}

export const appLog = {
  debug: (...args: unknown[]) => addEntry('debug', args),
  info: (...args: unknown[]) => addEntry('info', args),
  warn: (...args: unknown[]) => addEntry('warn', args),
  error: (...args: unknown[]) => addEntry('error', args),
};

/** Newest last. The array is replaced on every change, so it works as a snapshot. */
export function getLogEntries(): LogEntry[] {
  return entries;
}

export function clearLogEntries() {
  entries = [];
  listeners.forEach((listener) => listener());
}

export function subscribeLogs(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function formatLogEntries(list: LogEntry[]): string {
  return list
    .map((e) => `${new Date(e.timestamp).toISOString()} [${e.level.toUpperCase()}] ${e.message}`)
    .join('\n');
}

const CONSOLE_LEVELS = { log: 'debug', debug: 'debug', info: 'info', warn: 'warn', error: 'error' } as const;
type ConsoleMethod = keyof typeof CONSOLE_LEVELS;

const originals = new Map<ConsoleMethod, (...args: unknown[]) => void>();

const onWindowError = (event: ErrorEvent) => addEntry('error', [event.error ?? event.message]);
const onUnhandledRejection = (event: PromiseRejectionEvent) =>
  addEntry('error', ['Unhandled rejection:', event.reason]);

function startCapture() {
  if (originals.size > 0) return;
  (Object.keys(CONSOLE_LEVELS) as ConsoleMethod[]).forEach((method) => {
    const original = console[method].bind(console) as (...args: unknown[]) => void;
    originals.set(method, original);
    console[method] = (...args: unknown[]) => {
      addEntry(CONSOLE_LEVELS[method], args);
      original(...args);
    };
  });
  window.addEventListener('error', onWindowError);
  window.addEventListener('unhandledrejection', onUnhandledRejection);
}

function stopCapture() {
  originals.forEach((original, method) => {
    console[method] = original;
  });
  originals.clear();
  window.removeEventListener('error', onWindowError);
  window.removeEventListener('unhandledrejection', onUnhandledRejection);
}

/** Follows the debug logging setting, capturing console output while it is on. */
export function initLogger() {
  const apply = () => {
    if (getSettings().debugLoggingEnabled) startCapture();
    else stopCapture();
  };
  apply();
  subscribeSettings(apply);
}
