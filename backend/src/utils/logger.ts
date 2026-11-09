import winston from 'winston';
import path from 'path';
import fs from 'fs';

// Ensure log directory exists
const logDir = process.env.LOG_DIRECTORY || './logs';
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

// Credentials must never reach the log files or the console. Axios errors carry the
// whole request (headers with X-Plex-Token, sockets, TLS sessions), so they are reduced
// to the fields worth reading, and anything that looks like a secret is masked.
const SECRET_KEY = /token|authorization|cookie|password|secret|api[-_]?key/i;
const DROPPED_KEYS = new Set(['agent', 'socket', '_currentRequest', 'request', 'res', '_redirectable', '_header']);

export function redactString(text: string): string {
  return text
    .replace(/(x-plex-token["']?\s*[:=]\s*["']?)[^&\s"'\\,}]+/gi, '$1[redacted]')
    .replace(/([?&](?:token|access_token|api_key|apikey|key)=)[^&\s"']+/gi, '$1[redacted]')
    .replace(/(authorization["']?\s*[:=]\s*["']?(?:bearer\s+)?)[^\s"',}]+/gi, '$1[redacted]');
}

function summarizeAxiosError(err: any) {
  return {
    name: err.name,
    message: redactString(String(err.message ?? '')),
    code: err.code,
    status: err.response?.status,
    method: err.config?.method,
    url: err.config?.url ? redactString(String(err.config.url)) : undefined,
  };
}

export function redact(value: any, depth = 0, seen = new WeakSet<object>()): any {
  if (typeof value === 'string') return redactString(value);
  if (value === null || typeof value !== 'object') return value;
  if (seen.has(value)) return '[Circular]';
  seen.add(value);
  if (value.isAxiosError || (value.config && (value.request || value.response))) return summarizeAxiosError(value);
  if (Buffer.isBuffer(value)) return `[Buffer ${value.length} bytes]`;
  if (depth > 6) return '[Truncated]';
  if (Array.isArray(value)) return value.slice(0, 50).map((item) => redact(item, depth + 1, seen));
  const out: Record<string, any> = {};
  for (const key of Object.keys(value)) {
    if (DROPPED_KEYS.has(key)) continue;
    out[key] = SECRET_KEY.test(key) && typeof value[key] !== 'object' ? '[redacted]' : redact(value[key], depth + 1, seen);
  }
  if (value instanceof Error) {
    out.name = value.name;
    out.message = redactString(value.message);
    if (value.stack) out.stack = redactString(value.stack);
  }
  return out;
}

const redactFormat = winston.format((info) => {
  for (const key of Object.keys(info)) {
    if (key === 'level' || key === 'timestamp') continue;
    (info as any)[key] = redact((info as any)[key]);
  }
  return info;
});

// Define log format
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  redactFormat(),
  winston.format.splat(),
  winston.format.json()
);

// Console format for development
function safeStringify(obj: any): string {
  const seen = new WeakSet();
  try {
    return JSON.stringify(obj, function (_key, value) {
      if (typeof value === 'object' && value !== null) {
        if (seen.has(value)) return '[Circular]';
        seen.add(value);
      }
      if (value instanceof Error) {
        return { message: value.message, stack: value.stack, name: value.name };
      }
      return value;
    });
  } catch {
    try { return require('util').inspect(obj, { depth: 2, maxArrayLength: 10 }); } catch { return '[Unserializable]'; }
  }
}

const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'HH:mm:ss' }),
  winston.format.printf(({ timestamp, level, message, ...meta }) => {
    let msg = `${timestamp} [${level}] ${message}`;
    const metaKeys = Object.keys(meta);
    if (metaKeys.length > 0) {
      msg += ` ${safeStringify(meta)}`;
    }
    return msg;
  })
);

// Create logger instance
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
  format: logFormat,
  defaultMeta: { service: 'plex-media-backend' },
  transports: [
    // Error logs
    new winston.transports.File({
      filename: path.join(logDir, 'error.log'),
      level: 'error',
      maxsize: 5242880, // 5MB
      maxFiles: 5,
    }),
    // Combined logs
    new winston.transports.File({
      filename: path.join(logDir, 'combined.log'),
      maxsize: 5242880, // 5MB
      maxFiles: 5,
    }),
  ],
});

// Add console transport (always enabled for visibility)
logger.add(new winston.transports.Console({
  format: consoleFormat,
}));

// Create child loggers for different components
export const createLogger = (component: string) => {
  return logger.child({ component });
};

export default logger;
