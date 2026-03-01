#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-dev}"
source_uri="${2:-public://infinityui_healthcheck/source.jpg}"
style="${3:-thumbnail}"

case "$target" in
  dev) env_file=".env.dev" ;;
  stag) env_file=".env.stag" ;;
  prod) env_file=".env.prod" ;;
  *)
    if [[ -f "$target" ]]; then
      env_file="$target"
    else
      echo "Usage: scripts/healthcheck-media.sh [dev|stag|prod|/path/to/env] [source-uri] [image-style]" >&2
      exit 1
    fi
    ;;
esac

if [[ ! -f "$env_file" ]]; then
  echo "Env file not found: $env_file" >&2
  exit 1
fi

echo "[media-healthcheck] env=$env_file source=$source_uri style=$style"

./scripts/wait-for-drupal.sh "$env_file"

docker compose --env-file "$env_file" exec -T \
  -e HC_SOURCE_URI="$source_uri" \
  -e HC_STYLE="$style" \
  drupal-fpm \
  sh -lc 'cd /var/www/html && vendor/bin/drush php:script scripts/healthcheck-media.php'

echo "[media-healthcheck] completed successfully"
