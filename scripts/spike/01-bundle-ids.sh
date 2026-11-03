#!/usr/bin/env bash
# Bundle identifiers + executables of all apps inside the League bundle (no client needed).
source "$(dirname "$0")/lib.sh"
find "$LOL_APP" -maxdepth 5 -name "*.app" -print0 | while IFS= read -r -d '' app; do
  id="$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null || echo '?')"
  exe="$(defaults read "$app/Contents/Info" CFBundleExecutable 2>/dev/null || echo '?')"
  ui="$(defaults read "$app/Contents/Info" LSUIElement 2>/dev/null || echo '-')"
  printf '%-55s %-25s LSUIElement=%s  %s\n' "$id" "$exe" "$ui" "${app#"$LOL_APP"/}"
done
echo
echo "Running League processes:"
pgrep -il 'league|riot' || echo "  (none)"
