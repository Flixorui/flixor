/**
 * Removes hearing-impaired annotations from addon subtitle text: [MUSIC], (laughs),
 * ♪ lyrics ♪ and speaker labels like "JOHN:". Embedded tracks are rendered by mpv.
 */

const BRACKETED = /\[[^\]\n]*\]|\([^)\n]*\)|\{[^}\n]*\}/g;
const MUSIC_LINE = /^[\s♪♫#*-]*[♪♫#][^\n]*$/;
const SPEAKER_LABEL = /^(\s*-?\s*)[A-Z][A-Z0-9 .'-]{0,30}:\s*/;

export function removeHearingImpairedText(text: string): string {
  return text
    .split('\n')
    .map((line) => line.replace(BRACKETED, ' '))
    .filter((line) => !MUSIC_LINE.test(line))
    .map((line) => line.replace(SPEAKER_LABEL, '$1').replace(/\s{2,}/g, ' ').trim())
    .filter((line) => line.replace(/[-\s]/g, '').length > 0)
    .join('\n');
}
