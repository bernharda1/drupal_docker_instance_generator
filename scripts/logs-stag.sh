#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

service="${1:-}"
if [[ -n "$service" ]]; then
  docker compose --env-file .env.stag logs -f --tail 200 "$service"
else
  docker compose --env-file .env.stag logs -f --tail 200
fi
