import type { SubtitleCue } from '../../../stremio/types';

function parseTimestamp(raw: string): number {
  const match = raw.trim().match(/(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})/);
  if (!match) {
    return 0;
  }

  return (
    Number(match[1]) * 3600 +
    Number(match[2]) * 60 +
    Number(match[3]) +
    Number(match[4]) / 1000
  );
}

export function detectSubtitleFormat(content: string, url?: string): 'srt' | 'vtt' | 'unknown' {
  if (url?.toLowerCase().includes('.vtt')) {
    return 'vtt';
  }
  if (url?.toLowerCase().includes('.srt')) {
    return 'srt';
  }
  if (content.trimStart().startsWith('WEBVTT')) {
    return 'vtt';
  }
  if (content.match(/\d{1,2}:\d{2}:\d{2}[,.]\d{3}\s*-->\s*\d{1,2}:\d{2}:\d{2}[,.]\d{3}/)) {
    return 'srt';
  }
  return 'unknown';
}

function parseBlocks(content: string): SubtitleCue[] {
  const normalized = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
  const blocks = normalized.split(/\n\s*\n/);
  const cues: SubtitleCue[] = [];

  for (const block of blocks) {
    const lines = block.split('\n').map((line) => line.trim()).filter(Boolean);
    if (lines.length < 2) {
      continue;
    }

    const timeLine = lines.find((line) => line.includes('-->'));
    if (!timeLine) {
      continue;
    }

    const [startRaw, endRaw] = timeLine.split('-->');
    const startTime = parseTimestamp(startRaw);
    const endTime = parseTimestamp(endRaw);
    const timeIndex = lines.indexOf(timeLine);
    const text = lines.slice(timeIndex + 1).join('\n').trim();
    if (!text || endTime <= startTime) {
      continue;
    }

    cues.push({
      startTime,
      endTime,
      text,
    });
  }

  return cues;
}

export function parseSrt(content: string): SubtitleCue[] {
  return parseBlocks(content);
}

export function parseVtt(content: string): SubtitleCue[] {
  const withoutHeader = content.replace(/^WEBVTT[^\n]*\n+/i, '');
  return parseBlocks(withoutHeader);
}

export function parseSubtitleContent(content: string, url?: string): SubtitleCue[] {
  const format = detectSubtitleFormat(content, url);
  if (format === 'vtt') {
    return parseVtt(content);
  }
  return parseSrt(content);
}
