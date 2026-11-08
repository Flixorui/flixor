#!/usr/bin/env python3
"""Generate FlixorMac's Localizable.xcstrings (English entries) and keys.json.

Usage: gen_catalog.py [worktree-root] [derived-data-dir]

Sources:
  1. The compiler's .stringsdata files (build with SWIFT_EMIT_LOC_STRINGS, which the
     target has on): every SwiftUI literal, LocalizedStringKey parameter and
     String(localized:) call.
  2. Keys the compiler can't see: raw values of the enums rendered through
     `localizedRawValue` (ENUM_SOURCES below).

Existing translations in the catalog are kept (merge by key); run it again after
adding strings. Keys with no translatable text (numbers/symbols/format codes)
and technical or brand-only keys (DENY) are left out, so they fall back to the
key, which is the English text.
"""
import collections, glob, json, os, re, sys

# Usage: gen_string_catalog.py <repo-root> <derived-data-dir> [keys-output.json]
# Build the app first so the .stringsdata files are current.
if len(sys.argv) < 3:
    sys.exit(__doc__)
WT = sys.argv[1]
DD = sys.argv[2]
APP = f"{WT}/apps/macos/FlixorMac"
CATALOG = f"{APP}/Resources/Localizable.xcstrings"
KEYS_JSON = sys.argv[3] if len(sys.argv) > 3 else f"{WT}/apps/macos/scripts/string-catalog-keys.json"

# English singular for keys the app already branched on (1 -> singular).
PLURAL_ONE = {
    "%lld episodes watched": "%lld episode watched",
    "%lld new episodes": "%lld new episode",
    "%lld episodes": "%lld episode",
    "%lld Episodes": "%lld Episode",
    "%lld titles": "%lld title",
    "%lld people not shown": "%lld person not shown",
    "%lld sources": "%lld source",
    "%lld movies": "%lld movie",
    "%lld shows": "%lld show",
    "%lld eps": "%lld ep",
    "%lld entries": "%lld entry",
    "%lld items": "%lld item",
    "%lld likes": "%lld like",
    "%lld stream providers installed": "%lld stream provider installed",
    "%lld episodes • %@": "%lld episode • %@",
    "Request %lld Seasons": "Request %lld Season",
    "couldn't remove %lld saved progress entries": "couldn't remove %lld saved progress entry",
}
# Count-bearing keys whose English has no singular form today; translators still need plural forms.
PLURAL_SAME = {
    "%lld lists", "%lld replies", "%lld properties", "%lld Subs", "%lld seconds",
    "%lld items • %@", "%lld movies, in release order", "Preview (%lld titles)",
    "Preview (first %lld titles, more available)", "Remove %lld selected from %@",
    "Removed %lld titles from %@", "%lld+ titles",
    "No playable source arrived within %lld seconds. Showing all sources.",
    "No source matched your rules within %lld seconds. Showing all sources.",
}
DENY = {
    "4K", "4K HDR", "HDR", "IPv6", "FPS", "MaxCLL", "MaxFALL", "MPV", "HW Fmt", "Pixel Fmt", "FLIXOR",
    "Flixor", "Stremio", "Reddit", "Plex", "Trakt", "IMDb", "TMDB", "MDBList", "Overseerr",
    "Breaking Bad", "The Godfather", "The Office", "S3 E7", "S4 E2", "S5 E14", "45m", "2160p|4K",
    "CAM|TS|HDTS", "T", "D", "flixor.xyz", "%gx", "%lld MB", "%lld Kbps", "%lld Mbps", "%lldCH", "%lldp",
    "E%lld", "S%lld E%lld", "S%lld E%lld · %@", "TMDB %lld", "IMDb %@", "%lldms",
}
# enum name -> file, for raw values shown through `localizedRawValue`.
ENUM_SOURCES = {
    "NavItem": "App/RootView.swift",
    "Tab": "ViewModels/NewPopularViewModel.swift",
    "ContentType": "ViewModels/NewPopularViewModel.swift",
    "Period": "ViewModels/NewPopularViewModel.swift",
    "DownloadTab": "Views/Downloads/DownloadsView.swift",
    "ConnectionType": "Views/Settings/ServerConnectionView.swift",
}
SPEC = re.compile(r'%(?:\d+\$)?[-+#0 ]*[\d.]*(?:lld|ld|d|@|lf|f|g|s)')

def collect():
    keys = collections.defaultdict(set)
    pat = f"{DD}/Build/Intermediates.noindex/FlixorMac.build/Debug/FlixorMac.build/Objects-normal/*/*.stringsdata"
    for path in glob.glob(pat):
        data = json.load(open(path))
        stem = os.path.basename(data["source"]).rsplit(".", 1)[0]
        for table, entries in data["tables"].items():
            if table != "Localizable":
                raise SystemExit(f"unexpected table {table} in {path}")
            for entry in entries:
                if entry["key"]:
                    keys[entry["key"]].add(stem)
    if not keys:
        raise SystemExit(f"no .stringsdata under {DD}: build first")
    return keys

def enum_keys():
    found = {}
    for name, rel in ENUM_SOURCES.items():
        src = open(f"{APP}/{rel}", encoding="utf8").read()
        m = re.search(r'enum\s+%s\b[^{]*\{' % name, src)
        i, depth = m.end(), 1
        while depth:
            depth += (src[i] == "{") - (src[i] == "}")
            i += 1
        for value in re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', src[m.end():i]):
            found.setdefault(value, set()).add(name)
    return found

def keep(key):
    if key in DENY:
        return False
    return re.search(r"[A-Za-z]", SPEC.sub("", key)) is not None

def en_value(key):
    """Multi-argument keys get a positional English value, so translators can reorder."""
    specs = SPEC.findall(key)
    if len(specs) < 2:
        return None
    n = [0]
    def number(m):
        n[0] += 1
        return f"%{n[0]}$" + m.group(0)[1:]
    return SPEC.sub(number, key.replace("%%", "\0")).replace("\0", "%%")

def unit(value):
    return {"stringUnit": {"state": "new", "value": value}}

def entry(key, compiled, old):
    out = {}
    if not compiled:
        out["extractionState"] = "manual"
    locs = dict(old.get("localizations", {}))
    locs.pop("en", None)
    positional = en_value(key)
    if key in PLURAL_ONE or key in PLURAL_SAME:
        one = PLURAL_ONE.get(key, key)
        other = key
        if positional:
            one, other = en_value(one), positional
        locs["en"] = {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}
    elif positional:
        locs["en"] = unit(positional)
    if locs:
        out["localizations"] = locs
    return out

def write_json(path, obj):
    text = json.dumps(obj, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
    open(path, "w", encoding="utf8").write(text + "\n")

def main():
    compiled = collect()
    extra = enum_keys()
    previous = {}
    if os.path.exists(CATALOG):
        previous = json.load(open(CATALOG, encoding="utf8")).get("strings", {})
    strings, listing = {}, []
    for key in sorted(set(compiled) | set(extra)):
        if not keep(key):
            continue
        strings[key] = entry(key, key in compiled, previous.get(key, {}))
        where = sorted(compiled.get(key, set()) | extra.get(key, set()))
        comment = ", ".join(where[:3]) + (f" +{len(where) - 3} more" if len(where) > 3 else "")
        listing.append({"key": key, "comment": comment, "isPlural": key in PLURAL_ONE or key in PLURAL_SAME})
    write_json(CATALOG, {"sourceLanguage": "en", "strings": strings, "version": "1.0"})
    with open(KEYS_JSON, "w", encoding="utf8") as f:
        json.dump(listing, f, ensure_ascii=False, indent=1)
    missing = sorted((set(PLURAL_ONE) | PLURAL_SAME) - set(strings))
    print(f"{len(strings)} keys ({sum(1 for k in listing if k['isPlural'])} plural) -> {CATALOG}")
    if missing:
        print("WARNING plural keys not found:", missing)

if __name__ == "__main__":
    main()
