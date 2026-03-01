#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-dev}"
attempts="${2:-20}"
sleep_seconds="${3:-3}"

case "$target" in
  dev) env_file=".env.dev" ;;
  stag) env_file=".env.stag" ;;
  prod) env_file=".env.prod" ;;
  *)
    if [[ -f "$target" ]]; then
      env_file="$target"
    else
      echo "Usage: scripts/wait-for-drupal.sh [dev|stag|prod|/path/to/env] [attempts] [sleep-seconds]" >&2
      exit 1
    fi
    ;;
esac

if [[ ! -f "$env_file" ]]; then
  echo "Env file not found: $env_file" >&2
  exit 1
fi

echo "[wait-for-drupal] env=$env_file attempts=$attempts sleep=${sleep_seconds}s"

for i in $(seq 1 "$attempts"); do
  if docker compose --env-file "$env_file" exec -T drupal-fpm sh -lc 'cd /var/www/html && vendor/bin/drush status >/dev/null 2>&1'; then
    echo "[wait-for-drupal] ready after attempt $i"
    exit 0
  fi
  sleep "$sleep_seconds"
done

echo "[wait-for-drupal] Drupal not ready after $attempts attempts." >&2
exit 1
