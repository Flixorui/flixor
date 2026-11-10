/** Reading and editing the data folder's KEY=value files (flixor.env, service.env). Built-ins only. */

/** KEY=value lines; blank lines and # comments ignored; optional single or double quotes. */
export function parseEnvFile(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match || line.trimStart().startsWith('#')) continue;
    let value = match[2];
    const quoted = /^(['"])(.*)\1$/.exec(value);
    if (quoted) value = quoted[2];
    else value = value.replace(/\s+#.*$/, '');
    out[match[1]] = value;
  }
  return out;
}

/**
 * The file's text with KEY set to `value` (or removed when null). Replaces the
 * first KEY line in place and drops repeats; other lines and comments stay.
 */
export function setEnvValue(text: string, key: string, value: string | null): string {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`not a valid setting name: ${key}`);
  const encoded = value === null ? null : /[\s#'"]/.test(value) ? `"${value.replace(/"/g, '\\"')}"` : value;
  const lines = text.length ? text.replace(/\n$/, '').split('\n') : [];
  const out: string[] = [];
  let done = false;
  for (const line of lines) {
    if (new RegExp(`^\\s*(?:export\\s+)?${key}\\s*=`).test(line)) {
      if (!done && encoded !== null) out.push(`${key}=${encoded}`);
      done = true;
    } else {
      out.push(line);
    }
  }
  if (!done && encoded !== null) out.push(`${key}=${encoded}`);
  return out.length ? `${out.join('\n')}\n` : '';
}
