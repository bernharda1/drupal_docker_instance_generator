#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "WARNING: This will DELETE the PRODUCTION database volume (infrasightsolutions_postgres_data or infrasightsolutions_mysql_data)."
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

# Decide by configured DB driver in .env.prod
# Supported: pgsql (db-postgres), mysql (db-mysql)
driver="$(grep -E '^DRUPAL_DB_DRIVER=' .env.prod | tail -n1 | cut -d'=' -f2-)"

case "$driver" in
  pgsql)
    docker compose --env-file .env.prod rm -sf db-postgres || true
    docker volume rm infrasightsolutions_postgres_data || true
    docker compose --env-file .env.prod up -d db-postgres
    docker compose --env-file .env.prod ps db-postgres
    ;;
  mysql)
    docker compose --env-file .env.prod rm -sf db-mysql || true
    docker volume rm infrasightsolutions_mysql_data || true
    docker compose --env-file .env.prod up -d db-mysql
    docker compose --env-file .env.prod ps db-mysql
    ;;
  *)
    echo "Unsupported DRUPAL_DB_DRIVER in .env.prod: '$driver'" >&2
    exit 2
    ;;
esac

echo "Done. New clean production DB is starting."
