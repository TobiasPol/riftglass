#!/usr/bin/env bash
# Checks that every UI string the compiler extracted (run scripts/build.sh first) has a German
# translation in App/Sources/Localizable.xcstrings. Exit 1 lists the missing keys.
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 -I - <<'PY'
import glob, json, sys
objects = "build/DerivedData/Build/Intermediates.noindex/Riftglass.build/*/Riftglass.build/Objects-normal/*/*.stringsdata"
keys = {e["key"] for f in glob.glob(objects) for t in json.load(open(f)).get("tables", {}).values() for e in t}
if not keys:
    sys.exit("No .stringsdata found – run scripts/build.sh first.")
catalog = json.load(open("src/mac/App/Sources/Localizable.xcstrings"))["strings"]
def ok(key):
    entry = catalog.get(key, {})
    return entry.get("shouldTranslate") is False or "de" in entry.get("localizations", {})
missing = sorted(k for k in keys if not ok(k))
for key in missing:
    print(f"missing German translation: {key!r}")
print(f"{len(keys) - len(missing)}/{len(keys)} extracted strings translated")
sys.exit(1 if missing else 0)
PY
