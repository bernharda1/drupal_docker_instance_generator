#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./scripts/lib/reset-db-common.sh
resolve_db_targets_from_env_file .env.prod

echo "WARNING: This will DELETE the PRODUCTION database volume ($DB_VOLUME)."
read -r -p "Type 'yes' to continue: " confirm1
if [[ "$confirm1" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

read -r -p "Type 'PROD' to confirm production DB reset: " confirm2
if [[ "$confirm2" != "PROD" ]]; then
  echo "Aborted."
  exit 1
fi

docker compose --env-file .env.prod rm -sf "$DB_SERVICE" || true
docker volume rm "$DB_VOLUME" || true
docker compose --env-file .env.prod up -d "$DB_SERVICE"
docker compose --env-file .env.prod ps "$DB_SERVICE"

echo "Done. New clean production DB is starting."
