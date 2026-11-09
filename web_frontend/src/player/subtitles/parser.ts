export interface SubtitleCue {
  /** Seconds on the subtitle's own timeline, before the delay is applied. */
  start: number;
  end: number;
  text: string;
}

/** Parses SRT, WebVTT and ASS/SSA. The format is detected from the content. */
export function parseSubtitles(content: string, formatHint?: string): SubtitleCue[] {
  const text = content.replace(/^﻿/, '').replace(/\r\n?/g, '\n');
  const hint = formatHint?.toLowerCase();
  const cues = text.includes('[Events]') || hint === 'ass' || hint === 'ssa' ? parseAss(text) : parseTimedBlocks(text);
  return cues.sort((a, b) => a.start - b.start);
}

/** UTF-8, then UTF-16 with a byte order mark, then Windows-1252. */
export function decodeSubtitles(data: ArrayBuffer): string {
  const bytes = new Uint8Array(data);
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder('utf-16le').decode(bytes);
  if (bytes[0] === 0xfe && bytes[1] === 0xff) return new TextDecoder('utf-16be').decode(bytes);
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder('windows-1252').decode(bytes);
  }
}

/** "01:02:03,456", "01:02:03.456", "02:03.456" (VTT), "1:02:03.45". */
export function parseTimestamp(raw: string): number | null {
  const parts = raw.trim().replace(',', '.').split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  let seconds = 0;
  for (const part of parts.slice(0, -1)) {
    if (!/^\d+$/.test(part)) return null;
    seconds = seconds * 60 + Number(part);
  }
  const last = Number(parts[parts.length - 1]);
  return Number.isFinite(last) ? seconds * 60 + last : null;
}

function parseTimedBlocks(text: string): SubtitleCue[] {
  const cues: SubtitleCue[] = [];
  const lines = text.split('\n');
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (!line.includes('-->')) { index++; continue; }
    const [startRaw, endRaw] = line.split('-->');
    const start = parseTimestamp(startRaw);
    // VTT may append cue settings after the end time.
    const end = parseTimestamp((endRaw ?? '').trim().split(/\s+/)[0] ?? '');
    index++;
    if (start === null || end === null) continue;

    const body: string[] = [];
    while (index < lines.length && lines[index].trim() !== '') {
      if (lines[index].includes('-->')) break; // Missing blank line before the next cue.
      body.push(lines[index]);
      index++;
    }
    // A counter that belongs to the next cue.
    if (body.length > 0 && /^\s*\d+\s*$/.test(body[body.length - 1]) && lines[index]?.includes('-->')) body.pop();

    const cleaned = cleanMarkup(body.join('\n'));
    if (cleaned) cues.push({ start, end: Math.max(end, start), text: cleaned });
  }
  return cues;
}

function parseAss(text: string): SubtitleCue[] {
  const cues: SubtitleCue[] = [];
  const defaults = ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
  let inEvents = false;
  let format: string[] = [];

  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (line.startsWith('[')) { inEvents = line.toLowerCase() === '[events]'; continue; }
    if (!inEvents) continue;
    const lower = line.toLowerCase();
    if (lower.startsWith('format:')) {
      format = line.slice(7).split(',').map((field) => field.trim().toLowerCase());
      continue;
    }
    if (!lower.startsWith('dialogue:')) continue;

    const fields = format.length > 0 ? format : defaults;
    const startIndex = fields.indexOf('start');
    const endIndex = fields.indexOf('end');
    const textIndex = fields.indexOf('text');
    if (startIndex < 0 || endIndex < 0 || textIndex < 0) continue;

    // Text is the last field and may itself contain commas.
    const values = line.slice(9).split(',');
    if (values.length < fields.length) continue;
    const rest = values.slice(fields.length - 1).join(',');
    const row = [...values.slice(0, fields.length - 1), rest];

    const start = parseTimestamp(row[startIndex]);
    const end = parseTimestamp(row[endIndex]);
    if (start === null || end === null) continue;
    const body = row[textIndex]
      .replace(/\{[^}]*\}/g, '')
      .replace(/\\N/g, '\n')
      .replace(/\\n/g, '\n')
      .replace(/\\h/g, ' ')
      .trim();
    if (body) cues.push({ start, end: Math.max(end, start), text: body });
  }
  return cues;
}

function cleanMarkup(text: string): string {
  return text
    .replace(/<[^>]*>/g, '')
    .replace(/\{\\[^}]*\}/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .trim();
}

/** Strips hearing-impaired annotations: [MUSIC], (laughs), speaker labels and music lines. */
export function stripSdh(text: string): string {
  const lines = text
    .split('\n')
    .map((line) =>
      line
        .replace(/\[[^\]]*\]/g, '')
        .replace(/\([^)]*\)/g, '')
        .replace(/^\s*[-–—]?\s*[A-Z][A-Z0-9 .'#&-]*:\s*/, (match) => (match.trim().startsWith('-') ? '- ' : ''))
        .replace(/^[\s♪♫#*-]+$/, '')
        .trim(),
    )
    .filter((line) => line !== '' && line !== '-');
  return lines.join('\n');
}

export function applySdhFilter(cues: SubtitleCue[]): SubtitleCue[] {
  return cues
    .map((cue) => ({ ...cue, text: stripSdh(cue.text) }))
    .filter((cue) => cue.text !== '');
}

/** Index of the cue on screen at `position`, or -1. Cues are sorted by start. */
export function activeCueIndex(cues: SubtitleCue[], position: number): number {
  let low = 0;
  let high = cues.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (cues[mid].start <= position) low = mid + 1;
    else high = mid;
  }
  // Cues can overlap, so step back past any later-starting cue that already ended.
  for (let i = low - 1; i >= 0 && i >= low - 8; i--) {
    if (position <= cues[i].end) return i;
  }
  return -1;
}
