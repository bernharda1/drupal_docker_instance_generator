#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-keep}"

case "$mode" in
  keep)
    docker compose --env-file .env.stag down
    ;;
  purge)
    docker compose --env-file .env.stag down -v --remove-orphans
    ;;
  *)
    echo "Usage: scripts/down-stag.sh [keep|purge]" >&2
    exit 1
    ;;
esac
