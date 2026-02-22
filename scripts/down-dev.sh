#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-keep}"

case "$mode" in
  keep)
    docker compose --env-file .env.dev down
    ;;
  purge)
    docker compose --env-file .env.dev down -v --remove-orphans
    ;;
  *)
    echo "Usage: scripts/down-dev.sh [keep|purge]" >&2
    exit 1
    ;;
esac
