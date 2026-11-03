#!/usr/bin/env bash
# SwiftFormat (check only) + SwiftLint (strict). `scripts/lint.sh --fix` formats in place first.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--fix" ]]; then
  swiftformat src/mac scripts/spike
  swiftlint lint --fix --quiet
fi
swiftformat --lint src/mac scripts/spike
swiftlint lint --strict --quiet
