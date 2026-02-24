#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SITE_DIR="drupal/web/sites/default"
SETTINGS_FILE="$SITE_DIR/settings.php"
DEFAULT_SETTINGS_FILE="$SITE_DIR/default.settings.php"

LOCK_SETTINGS=0

usage() {
  cat <<'EOF'
Usage: scripts/ensure-settings-local.sh [--lock]

Sorgt dafür, dass:
- sites/default/settings.php existiert
- settings.php für den Installer schreibbar ist (0666), außer mit --lock (0444)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --lock)
      LOCK_SETTINGS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ ! -d "$SITE_DIR" ]; then
  echo "Site directory not found: $SITE_DIR" >&2
  exit 2
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  if [ -f "$DEFAULT_SETTINGS_FILE" ]; then
    cp "$DEFAULT_SETTINGS_FILE" "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE from default.settings.php"
  else
    cat > "$SETTINGS_FILE" <<'PHP'
<?php

declare(strict_types=1);
PHP
    echo "Created minimal $SETTINGS_FILE"
  fi
fi

sanitize_settings_file() {
  local file="$1"
  local tmp

  tmp="$(mktemp)"

  perl -0777 -pe '
    s/\n\$databases\[\x27default\x27\]\[\x27default\x27\]\s*=\s*array\s*\(\n(?:.*\n)*?\);\n?/\n/sg;
    s/\n\$settings\[\x27hash_salt\x27\]\s*=\s*\x27[^\x27]*\x27;\n?/\n/sg;
  ' "$file" > "$tmp"

  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    echo "Sanitized installer static DB/hash_salt overrides in $file"
  else
    rm -f "$tmp"
  fi
}

sanitize_settings_file "$SETTINGS_FILE"

if [ "$LOCK_SETTINGS" -eq 1 ]; then
  chmod 0444 "$SETTINGS_FILE"
  echo "Locked $SETTINGS_FILE to 0444"
else
  chmod 0666 "$SETTINGS_FILE"
  echo "Set $SETTINGS_FILE to 0666 (installer-writable)"
fi
