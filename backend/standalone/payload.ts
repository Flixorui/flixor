/**
 * The standalone executable's payload: a folder tree (server bundle, native
 * add-ons, web app) packed into one gzip buffer. Built-ins only, because the
 * executable's entry point can't load anything else.
 *
 * Layout before compression: "FLXP1\n", then per entry
 *   kind (u8: 0 file, 1 symlink) | mode (u16) | path length (u32) | path (utf-8)
 *   | data length (u32) | data (file bytes, or the link target)
 */
import fs from 'fs';
import path from 'path';
import zlib from 'zlib';

const MAGIC = Buffer.from('FLXP1\n');
const FILE = 0;
const SYMLINK = 1;

interface Entry {
  kind: number;
  mode: number;
  rel: string;
  data: Buffer;
}

function* walk(root: string, rel = ''): Generator<Entry> {
  const dir = path.join(root, rel);
  for (const name of fs.readdirSync(dir).sort()) {
    const relPath = rel ? `${rel}/${name}` : name;
    const full = path.join(root, relPath);
    const stat = fs.lstatSync(full);
    if (stat.isSymbolicLink()) {
      yield { kind: SYMLINK, mode: 0o777, rel: relPath, data: Buffer.from(fs.readlinkSync(full)) };
    } else if (stat.isDirectory()) {
      yield* walk(root, relPath);
    } else if (stat.isFile()) {
      yield { kind: FILE, mode: stat.mode & 0o777, rel: relPath, data: fs.readFileSync(full) };
    }
  }
}

/** Packs every file and symlink under `root`. */
export function pack(root: string): Buffer {
  const parts: Buffer[] = [MAGIC];
  for (const entry of walk(root)) {
    const name = Buffer.from(entry.rel);
    const head = Buffer.alloc(1 + 2 + 4);
    head.writeUInt8(entry.kind, 0);
    head.writeUInt16LE(entry.mode, 1);
    head.writeUInt32LE(name.length, 3);
    const size = Buffer.alloc(4);
    size.writeUInt32LE(entry.data.length, 0);
    parts.push(head, name, size, entry.data);
  }
  return zlib.gzipSync(Buffer.concat(parts), { level: 9 });
}

/** A path from the payload, refused if it would land outside `dest`. */
function target(dest: string, rel: string): string {
  const full = path.resolve(dest, rel);
  if (full !== dest && !full.startsWith(dest + path.sep)) throw new Error(`payload path escapes its folder: ${rel}`);
  return full;
}

/** Writes the packed tree into `dest`, which must not exist yet. Returns the number of entries. */
export function unpack(packed: Buffer | Uint8Array, dest: string): number {
  const raw = zlib.gunzipSync(packed);
  if (!raw.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error('not a Flixor payload');
  const root = path.resolve(dest);
  fs.mkdirSync(root, { recursive: true });
  let offset = MAGIC.length;
  let count = 0;
  while (offset < raw.length) {
    const kind = raw.readUInt8(offset);
    const mode = raw.readUInt16LE(offset + 1);
    const nameLength = raw.readUInt32LE(offset + 3);
    offset += 7;
    const rel = raw.subarray(offset, offset + nameLength).toString();
    offset += nameLength;
    const dataLength = raw.readUInt32LE(offset);
    offset += 4;
    const data = raw.subarray(offset, offset + dataLength);
    offset += dataLength;

    const full = target(root, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    if (kind === SYMLINK) {
      const link = data.toString();
      target(root, path.join(path.dirname(rel), link)); // links stay inside the tree too
      fs.symlinkSync(link, full);
    } else if (kind === FILE) {
      fs.writeFileSync(full, data, { mode });
    } else {
      throw new Error(`unknown payload entry kind ${kind}`);
    }
    count += 1;
  }
  return count;
}
