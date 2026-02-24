#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./scripts/lib/reset-db-common.sh
resolve_db_targets_from_env_file .env.stag

echo "WARNING: This will DELETE the STAGING database volume ($DB_VOLUME)."
read -r -p "Type 'yes' to continue: " confirm1
if [[ "$confirm1" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

read -r -p "Type 'STAG' to confirm staging DB reset: " confirm2
if [[ "$confirm2" != "STAG" ]]; then
  echo "Aborted."
  exit 1
fi

docker compose --env-file .env.stag rm -sf "$DB_SERVICE" || true
docker volume rm "$DB_VOLUME" || true

docker compose --env-file .env.stag up -d "$DB_SERVICE"

echo "Done. New clean staging DB is starting."
docker compose --env-file .env.stag ps "$DB_SERVICE"
