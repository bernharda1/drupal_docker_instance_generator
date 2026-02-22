#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "WARNING: This will DELETE the STAGING database volume (infrasightsolutions_mysql_data)."
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

docker compose --env-file .env.stag rm -sf db-mysql || true
docker volume rm infrasightsolutions_mysql_data || true

docker compose --env-file .env.stag up -d db-mysql

echo "Done. New clean staging DB is starting."
docker compose --env-file .env.stag ps db-mysql
