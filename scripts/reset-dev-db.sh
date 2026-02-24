#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

source ./scripts/lib/reset-db-common.sh
resolve_db_targets_from_env_file .env.dev

echo "This will DELETE the dev database volume ($DB_VOLUME)."
read -r -p "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Stop/remove only db container, then remove its volume and recreate it cleanly.
docker compose --env-file .env.dev rm -sf "$DB_SERVICE" || true
docker volume rm "$DB_VOLUME" || true

docker compose --env-file .env.dev up -d "$DB_SERVICE"

echo "Done. New clean dev DB is starting."
docker compose --env-file .env.dev ps "$DB_SERVICE"
