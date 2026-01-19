/**
 * Centralized logging system with circular buffer
 * Supports debug, info, warn, error levels with sensitive data redaction
 * Intercepts console methods to capture all app logs
 */

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogEntry {
  timestamp: Date;
  level: LogLevel;
  message: string;
  data?: string;
}

// Patterns to redact from logs
const SENSITIVE_PATTERNS = [
  /token["\s:=]+["']?[\w-]+["']?/gi,
  /password["\s:=]+["']?[\w-]+["']?/gi,
  /apikey["\s:=]+["']?[\w-]+["']?/gi,
  /api_key["\s:=]+["']?[\w-]+["']?/gi,
  /secret["\s:=]+["']?[\w-]+["']?/gi,
  /authorization["\s:=]+["']?[\w-]+["']?/gi,
  /bearer\s+[\w-]+/gi,
  /X-Plex-Token["\s:=]+["']?[\w-]+["']?/gi,
];

// Store original console methods
const originalConsole = {
  log: console.log.bind(console),
  debug: console.debug.bind(console),
  info: console.info.bind(console),
  warn: console.warn.bind(console),
  error: console.error.bind(console),
};

class AppLogger {
  private logs: LogEntry[] = [];
  private maxEntries = 500;
  private debugEnabled = false;
  private listeners: Set<() => void> = new Set();
  private isIntercepting = false;
  private isLogging = false; // Prevent infinite loops

  /**
   * Enable or disable debug logging
   * When enabled, intercepts all console methods
   */
  setDebugEnabled(enabled: boolean): void {
    this.debugEnabled = enabled;

    if (enabled) {
      this.installConsoleInterceptors();
    } else {
      this.removeConsoleInterceptors();
    }

    this.addEntry('info', `Debug logging ${enabled ? 'enabled' : 'disabled'}`);
  }

  /**
   * Check if debug logging is enabled
   */
  isDebugEnabled(): boolean {
    return this.debugEnabled;
  }

  /**
   * Install console interceptors to capture all logs
   */
  private installConsoleInterceptors(): void {
    if (this.isIntercepting) return;
    this.isIntercepting = true;

    console.log = (...args: any[]) => {
      this.captureConsole('debug', args);
      originalConsole.log(...args);
    };

    console.debug = (...args: any[]) => {
      this.captureConsole('debug', args);
      originalConsole.debug(...args);
    };

    console.info = (...args: any[]) => {
      this.captureConsole('info', args);
      originalConsole.info(...args);
    };

    console.warn = (...args: any[]) => {
      this.captureConsole('warn', args);
      originalConsole.warn(...args);
    };

    console.error = (...args: any[]) => {
      this.captureConsole('error', args);
      originalConsole.error(...args);
    };
  }

  /**
   * Remove console interceptors and restore original methods
   */
  private removeConsoleInterceptors(): void {
    if (!this.isIntercepting) return;
    this.isIntercepting = false;

    console.log = originalConsole.log;
    console.debug = originalConsole.debug;
    console.info = originalConsole.info;
    console.warn = originalConsole.warn;
    console.error = originalConsole.error;
  }

  /**
   * Capture console output
   */
  private captureConsole(level: LogLevel, args: any[]): void {
    // Prevent infinite loops
    if (this.isLogging) return;

    const message = args
      .map((arg) => {
        if (typeof arg === 'string') return arg;
        try {
          return JSON.stringify(arg);
        } catch {
          return String(arg);
        }
      })
      .join(' ');

    this.addEntry(level, message);
  }

  /**
   * Add a listener for log changes
   */
  addListener(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notifyListeners(): void {
    this.listeners.forEach((listener) => listener());
  }

  /**
   * Redact sensitive data from a string
   */
  private redact(text: string): string {
    let result = text;
    for (const pattern of SENSITIVE_PATTERNS) {
      result = result.replace(pattern, '[REDACTED]');
    }
    return result;
  }

  /**
   * Safely stringify data for logging
   */
  private stringifyData(data: any): string | undefined {
    if (data === undefined) return undefined;
    try {
      const str = typeof data === 'string' ? data : JSON.stringify(data, null, 2);
      return this.redact(str);
    } catch {
      return '[Unable to stringify]';
    }
  }

  /**
   * Add a log entry (internal)
   */
  private addEntry(level: LogLevel, message: string, data?: any): void {
    this.isLogging = true;

    try {
      const entry: LogEntry = {
        timestamp: new Date(),
        level,
        message: this.redact(message),
        data: this.stringifyData(data),
      };

      this.logs.push(entry);

      // Maintain circular buffer
      if (this.logs.length > this.maxEntries) {
        this.logs.shift();
      }

      this.notifyListeners();
    } finally {
      this.isLogging = false;
    }
  }

  /**
   * Log debug message (only captured when debug mode enabled)
   */
  debug(message: string, data?: any): void {
    if (!this.debugEnabled) return;
    this.addEntry('debug', message, data);
    originalConsole.debug(`[DEBUG] ${message}`, data ?? '');
  }

  /**
   * Log info message
   */
  info(message: string, data?: any): void {
    this.addEntry('info', message, data);
    originalConsole.info(`[INFO] ${message}`, data ?? '');
  }

  /**
   * Log warning message
   */
  warn(message: string, data?: any): void {
    this.addEntry('warn', message, data);
    originalConsole.warn(`[WARN] ${message}`, data ?? '');
  }

  /**
   * Log error message
   */
  error(message: string, data?: any): void {
    this.addEntry('error', message, data);
    originalConsole.error(`[ERROR] ${message}`, data ?? '');
  }

  /**
   * Get all logs
   */
  getLogs(): LogEntry[] {
    return [...this.logs];
  }

  /**
   * Get log count
   */
  getLogCount(): number {
    return this.logs.length;
  }

  /**
   * Clear all logs
   */
  clearLogs(): void {
    this.logs = [];
    this.notifyListeners();
  }

  /**
   * Export logs as formatted string for sharing
   */
  exportLogs(): string {
    const lines = this.logs.map((entry) => {
      const time = entry.timestamp.toISOString();
      const level = entry.level.toUpperCase().padEnd(5);
      let line = `[${time}] ${level} ${entry.message}`;
      if (entry.data) {
        line += `\n  Data: ${entry.data}`;
      }
      return line;
    });
    return lines.join('\n');
  }
}

// Singleton instance
export const appLogger = new AppLogger();
