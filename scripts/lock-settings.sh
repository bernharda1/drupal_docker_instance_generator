#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -x ./scripts/ensure-settings-local.sh ]; then
  echo "Missing executable helper: ./scripts/ensure-settings-local.sh" >&2
  echo "Run: chmod +x scripts/ensure-settings-local.sh" >&2
  exit 2
fi

./scripts/ensure-settings-local.sh --lock

echo "settings.php is now locked (0444)."
echo "To unlock for installer/config changes: ./scripts/ensure-settings-local.sh"
