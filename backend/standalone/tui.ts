/**
 * The `flixor` dashboard: live server status, recent log lines and one-key
 * actions. Plain ANSI on the terminal's alternate screen; built-ins only.
 */
import readline from 'readline';
import {
  compareVersions, getStatus, latestVersion, openInBrowser, restartService, runInstaller, serviceDescription,
  serviceLog, serviceState, startService, stateLabel, stopService, tailLines, writeSetting, type Install, type Status,
} from './control';

const color = !process.env.NO_COLOR;
const sgr = (code: string) => (text: string) => (color ? `\x1b[${code}m${text}\x1b[0m` : text);
const bold = sgr('1');
const dim = sgr('2');
const green = sgr('32');
const red = sgr('31');
const yellow = sgr('33');
const cyan = sgr('36');

/** Visible length, ignoring color codes. */
export const visibleLength = (text: string) => text.replace(/\x1b\[[0-9;]*m/g, '').length;

function fit(text: string, width: number): string {
  if (visibleLength(text) <= width) return text;
  // Long plain text (log lines): cut, keeping it readable.
  const plain = text.replace(/\x1b\[[0-9;]*m/g, '');
  return `${plain.slice(0, Math.max(0, width - 1))}…`;
}

export interface View {
  mode: 'main' | 'logs' | 'port';
  message?: string;
  input?: string;
  busy?: string;
}

/** A log line for the dashboard: no colors, no trailing JSON metadata from the logger. */
export const cleanLogLine = (line: string) => line.replace(/\x1b\[[0-9;]*m/g, '').replace(/\s+\{"[^{}]*\}\s*$/, '');

/** The whole screen as text. Pure, for tests. */
export function render(status: Status, logs: string[], view: View, width: number, height: number): string {
  const w = Math.max(40, Math.min(width, 100));
  const rule = dim('─'.repeat(w));
  const state = stateLabel(status);
  const dot = state === 'running' ? green('●') : state === 'stopped' ? red('●') : yellow('●');
  const stateText = state === 'running' ? green('Running') : state === 'stopped' ? red('Stopped') : yellow(state[0].toUpperCase() + state.slice(1));
  const details = status.service.pid ? dim(`  pid ${status.service.pid}${status.uptime ? ` · up ${status.uptime}` : ''}`) : '';
  const update = status.latest && compareVersions(status.latest, status.version) > 0
    ? yellow(`${status.latest} available, press u`)
    : status.latest ? dim('up to date') : dim('checking…');
  const row = (label: string, value: string) => fit(`  ${dim(label.padEnd(9))} ${value}`, w);

  const lines = [
    fit(`  ${bold(red('FLIXOR'))} ${bold('server')}  ${dim(status.version)}`, w),
    rule,
    row('Status', `${dot} ${stateText}${details}`),
    row('Open', cyan(status.url)),
    ...(status.lanUrl ? [row('Network', cyan(status.lanUrl))] : []),
    row('Service', `${serviceDescription(status.install)}${status.install.kind === 'none' ? '' : status.service.enabled === false ? dim(' · off until started') : dim(' · starts automatically')}`),
    row('Data', status.install.dataDir),
    row('FFmpeg', status.ffmpeg || yellow('not set, addon conversions need it')),
    row('Version', update),
    rule,
  ];

  const footerLines = 3;
  if (view.mode === 'logs') {
    const room = Math.max(3, height - 4); // header, rule, rule, footer
    const shown = logs.slice(-room).map((line) => fit(`  ${cleanLogLine(line)}`, w));
    return [fit(`  ${bold('Log')}  ${dim(serviceLog(status.install))}`, w), rule, ...shown, rule, `  ${dim('q / esc')} back`].join('\n');
  }

  const room = Math.max(0, height - lines.length - footerLines - 1);
  lines.push(fit(`  ${bold('Recent log')}`, w));
  const recent = logs.slice(-room);
  lines.push(...(recent.length ? recent.map((line) => fit(`  ${dim(cleanLogLine(line))}`, w)) : [`  ${dim('(no log yet)')}`]));
  lines.push(rule);

  const running = status.service.running || status.healthy;
  const key = (k: string, label: string) => `${bold(k)} ${label}`;
  const actions = [
    key('s', running ? 'stop' : 'start'), key('r', 'restart'), key('o', 'open'), key('l', 'logs'),
    key('p', 'port'), key('u', 'update'), key('q', 'quit'),
  ].join(dim('  ·  '));
  lines.push(fit(`  ${actions}`, w));
  if (view.mode === 'port') lines.push(`  New port: ${view.input ?? ''}${color ? '\x1b[5m_\x1b[0m' : '_'}  ${dim('enter to apply, esc to cancel')}`);
  else if (view.busy) lines.push(`  ${yellow(view.busy)}`);
  else if (view.message) lines.push(`  ${view.message}`);
  return lines.join('\n');
}

/** Runs the dashboard until the user quits. */
export async function runTui(install: Install, version: string): Promise<number> {
  const out = process.stdout;
  const input = process.stdin;
  let status = await getStatus(install, version, null);
  let latest: string | null | undefined;
  let logs = tailLines(serviceLog(install), 200);
  const view: View = { mode: 'main' };
  let closed = false;
  let pendingUpdate = false;

  const draw = () => {
    if (closed) return;
    const screen = render({ ...status, latest }, logs, view, out.columns || 80, out.rows || 24);
    out.write(`\x1b[H\x1b[2J${screen}`);
  };
  const refresh = async () => {
    status = await getStatus(install, version, latest);
    logs = tailLines(serviceLog(install), 200);
    draw();
  };

  out.write('\x1b[?1049h\x1b[?25l'); // alternate screen, hide cursor
  const restore = () => {
    if (closed) return;
    closed = true;
    out.write('\x1b[?25h\x1b[?1049l');
    if (input.isTTY) input.setRawMode(false);
  };
  process.on('exit', restore);

  readline.emitKeypressEvents(input);
  if (input.isTTY) input.setRawMode(true);
  input.resume();

  const timer = setInterval(() => { void refresh(); }, 1500);
  out.on('resize', draw);
  latestVersion(install).then((v) => { latest = v; draw(); }).catch(() => { latest = null; });
  draw();

  const act = async (label: string, action: () => void | Promise<void>, done: string) => {
    view.busy = label;
    draw();
    try {
      await action();
      view.message = green(done);
    } catch (error) {
      view.message = red((error as Error).message);
    }
    view.busy = undefined;
    await refresh();
  };

  return new Promise<number>((resolve) => {
    const quit = () => {
      clearInterval(timer);
      input.removeAllListeners('keypress');
      restore();
      input.pause();
      if (pendingUpdate) {
        process.stdout.write('Updating Flixor…\n');
        resolve(runInstaller(install, []));
      } else {
        resolve(0);
      }
    };

    input.on('keypress', (text: string | undefined, key: { name?: string; ctrl?: boolean; sequence?: string }) => {
      if (key?.ctrl && key.name === 'c') return quit();
      if (view.busy) return;

      if (view.mode === 'logs') {
        if (key?.name === 'escape' || key?.name === 'q') view.mode = 'main';
        return draw();
      }

      if (view.mode === 'port') {
        if (key?.name === 'escape') {
          view.mode = 'main';
          view.input = undefined;
        } else if (key?.name === 'return') {
          const port = view.input ?? '';
          view.mode = 'main';
          view.input = undefined;
          if (!/^\d{1,5}$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
            view.message = red(`Not a port number: ${port || '(empty)'}`);
          } else {
            void act(`Switching to port ${port}…`, () => {
              writeSetting(install, 'PORT', port);
              if (serviceState(install).running) restartService(install);
            }, `Now on port ${port}.`);
            return;
          }
        } else if (key?.name === 'backspace') {
          view.input = (view.input ?? '').slice(0, -1);
        } else if (text && /^\d$/.test(text) && (view.input ?? '').length < 5) {
          view.input = (view.input ?? '') + text;
        }
        return draw();
      }

      switch (key?.name ?? text) {
        case 'q':
        case 'escape':
          return quit();
        case 's': {
          const running = status.service.running || status.healthy;
          return void act(running ? 'Stopping…' : 'Starting…', () => (running ? stopService(install) : startService(install)),
            running ? 'Stopped. It stays off until you start it again.' : 'Started.');
        }
        case 'r':
          return void act('Restarting…', () => restartService(install), 'Restarted.');
        case 'o':
          openInBrowser(status.url);
          view.message = `Opened ${status.url}`;
          return draw();
        case 'l':
          view.mode = 'logs';
          return draw();
        case 'p':
          view.mode = 'port';
          view.input = '';
          view.message = undefined;
          return draw();
        case 'u':
          if (latest && compareVersions(latest, version) <= 0) {
            view.message = dim(`Already up to date (${version}).`);
            return draw();
          }
          pendingUpdate = true;
          return quit();
        default:
          return undefined;
      }
    });
  });
}
