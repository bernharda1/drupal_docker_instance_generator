#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "This will DELETE the dev MySQL volume (infrasightsolutions_mysql_data)."
read -r -p "Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Stop/remove only db container, then remove its volume and recreate it cleanly.
docker compose --env-file .env.dev rm -sf db-mysql || true
docker volume rm infrasightsolutions_mysql_data || true

docker compose --env-file .env.dev up -d db-mysql

echo "Done. New clean dev DB is starting."
docker compose --env-file .env.dev ps db-mysql
