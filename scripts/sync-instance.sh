#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <source-env> <target-env> [--yes]

Synchronize Drupal from source environment to target environment.
Supported env names: dev, stag, prod (requires .env.dev/.env.stag/.env.prod files present).

What it does:
 - Ensures source and target compose stacks are up
 - Dumps the database from source and imports into target
 - Copies `/var/www/html/web/sites/default/files` from source to target
 - Attempts a `drush cr` in target (if available)

This script must be run from the repository root.
EOF
}

if [ "$#" -lt 2 ]; then
  usage
  exit 1
fi

SRC=$1
TGT=$2
CONFIRM=false
if [ "${3:-}" = "--yes" ]; then
  CONFIRM=true
fi

for e in "$SRC" "$TGT"; do
  if [ ! -f ".env.$e" ]; then
    echo "Env file .env.$e not found. Supported: .env.dev .env.stag .env.prod" >&2
    exit 2
  fi
done

if [ "$SRC" = "$TGT" ]; then
  echo "Source and target must differ" >&2
  exit 3
fi

if [ "$CONFIRM" = false ]; then
  echo "About to sync from '$SRC' -> '$TGT'. This will overwrite target DB and files."
  read -p "Proceed? (type 'yes' to continue): " ans
  if [ "$ans" != "yes" ]; then
    echo "Aborted."; exit 0
  fi
fi

TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

get_env_val() {
  # $1: envfile, $2: key
  awk -F= -v key="$2" '$1==key{print substr($0,index($0,$2))}' "$1" | sed 's/^"\?//;s/"\?$//'
}

echo "Bringing up minimal services in source and target..."
# Determine DB driver from source env
DRIVER=$(awk -F= '/^DRUPAL_DB_DRIVER/{print $2}' .env.$SRC | tr -d '"' || true)
DRIVER=${DRIVER:-mysql}

# Determine compose project names (fall back to proj_<env>)
SRC_PROJECT=$(awk -F= '/^COMPOSE_PROJECT_NAME/{print $2}' .env.$SRC | tr -d '"' || true)
SRC_PROJECT=${SRC_PROJECT:-proj_$SRC}
TGT_PROJECT=$(awk -F= '/^COMPOSE_PROJECT_NAME/{print $2}' .env.$TGT | tr -d '"' || true)
TGT_PROJECT=${TGT_PROJECT:-proj_$TGT}

start_services() {
  local envfile="$1"
  local project="$2"
  echo "Starting compose for $envfile (project=$project) (db + drupal)"
  docker compose --env-file "$envfile" --project-name "$project" up -d db-mysql db-mariadb db-postgres drupal-fpm || true
}

start_services ".env.$SRC" "$SRC_PROJECT"
start_services ".env.$TGT" "$TGT_PROJECT"

wait_container() {
  local name="$1"
  local tries=0
  until docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; do
    tries=$((tries+1))
    if [ $tries -gt 30 ]; then
      echo "Container $name did not start" >&2
      return 1
    fi
    sleep 1
  done
}

# Map driver -> container name and credential keys
case "$DRIVER" in
  mysql)
    SRC_DB_CONTAINER=infrasight_db_mysql
    TGT_DB_CONTAINER=infrasight_db_mysql
    SRC_USER_KEY=MYSQL_USER
    SRC_PASS_KEY=MYSQL_PASSWORD
    SRC_DB_KEY=MYSQL_DATABASE
    TGT_USER_KEY=MYSQL_USER
    TGT_PASS_KEY=MYSQL_PASSWORD
    TGT_DB_KEY=MYSQL_DATABASE
    ;;
  mariadb)
    SRC_DB_CONTAINER=infrasight_db_mariadb
    TGT_DB_CONTAINER=infrasight_db_mariadb
    SRC_USER_KEY=MARIADB_USER
    SRC_PASS_KEY=MARIADB_PASSWORD
    SRC_DB_KEY=MARIADB_DATABASE
    TGT_USER_KEY=MARIADB_USER
    TGT_PASS_KEY=MARIADB_PASSWORD
    TGT_DB_KEY=MARIADB_DATABASE
    ;;
  postgres)
    SRC_DB_CONTAINER=infrasight_db_postgres
    TGT_DB_CONTAINER=infrasight_db_postgres
    SRC_USER_KEY=POSTGRES_USER
    SRC_PASS_KEY=POSTGRES_PASSWORD
    SRC_DB_KEY=POSTGRES_DB
    TGT_USER_KEY=POSTGRES_USER
    TGT_PASS_KEY=POSTGRES_PASSWORD
    TGT_DB_KEY=POSTGRES_DB
    ;;
  *)
    echo "Unsupported DRUPAL_DB_DRIVER: $DRIVER" >&2; exit 4;;
esac

echo "Waiting for DB containers to be running..."
wait_container "$SRC_DB_CONTAINER" || true
wait_container "$TGT_DB_CONTAINER" || true
wait_container infrasight_drupal_fpm || true

echo "Dumping database from source ($SRC -> container $SRC_DB_CONTAINER)..."
case "$DRIVER" in
  mysql|mariadb)
    SRC_USER=$(get_env_val .env.$SRC "$SRC_USER_KEY")
    SRC_PASS=$(get_env_val .env.$SRC "$SRC_PASS_KEY")
    SRC_DB=$(get_env_val .env.$SRC "$SRC_DB_KEY")
    # use MYSQL_PWD to avoid exposing password in process list and avoid tablespaces
    docker exec -i -e MYSQL_PWD="$SRC_PASS" "$SRC_DB_CONTAINER" sh -c "mysqldump -u\"$SRC_USER\" --single-transaction --quick --no-tablespaces --set-gtid-purged=OFF --skip-lock-tables \"$SRC_DB\"" > "$TMPDIR/db.sql"
    ;;
  postgres)
    SRC_USER=$(get_env_val .env.$SRC "$SRC_USER_KEY")
    SRC_PASS=$(get_env_val .env.$SRC "$SRC_PASS_KEY")
    SRC_DB=$(get_env_val .env.$SRC "$SRC_DB_KEY")
    docker exec -i -e PGPASSWORD="$SRC_PASS" "$SRC_DB_CONTAINER" sh -c "pg_dump -U \"$SRC_USER\" -d \"$SRC_DB\"" > "$TMPDIR/db.sql"
    ;;
esac

echo "Importing database into target ($TGT -> container $TGT_DB_CONTAINER)..."
# Create backups of target DB and files before overwriting
BACKUP_DIR="./backups/${TGT}/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"
echo "Creating target backups in $BACKUP_DIR"
case "$DRIVER" in
  mysql|mariadb)
    TGT_USER=$(get_env_val .env.$TGT "$TGT_USER_KEY")
    TGT_PASS=$(get_env_val .env.$TGT "$TGT_PASS_KEY")
    TGT_DB=$(get_env_val .env.$TGT "$TGT_DB_KEY")
    echo "Backing up target database to $BACKUP_DIR/target-db.sql.gz"
    # use MYSQL_PWD to avoid password leakage
    docker exec -i -e MYSQL_PWD="$TGT_PASS" "$TGT_DB_CONTAINER" sh -c "mysqldump -u\"$TGT_USER\" --single-transaction --quick --no-tablespaces --set-gtid-purged=OFF --skip-lock-tables \"$TGT_DB\"" | gzip > "$BACKUP_DIR/target-db.sql.gz"
    ;;
  postgres)
    TGT_USER=$(get_env_val .env.$TGT "$TGT_USER_KEY")
    TGT_PASS=$(get_env_val .env.$TGT "$TGT_PASS_KEY")
    TGT_DB=$(get_env_val .env.$TGT "$TGT_DB_KEY")
    echo "Backing up target database to $BACKUP_DIR/target-db.sql.gz"
    docker exec -i "$TGT_DB_CONTAINER" sh -c "PGPASSWORD=\"$TGT_PASS\" pg_dump -U \"$TGT_USER\" -d \"$TGT_DB\"" | gzip > "$BACKUP_DIR/target-db.sql.gz"
    ;;
esac

echo "Backing up target files to $BACKUP_DIR/target-files.tar.gz"
docker exec -i "$TGT_FPM" sh -c 'cd /var/www/html/web/sites/default && tar -czf - files' > "$BACKUP_DIR/target-files.tar.gz" || true

echo "Backups written to $BACKUP_DIR"

# Put target into maintenance mode if possible
echo "Enabling maintenance mode on target (if drush available)"
docker exec "$TGT_FPM" sh -c 'if [ -x vendor/bin/drush ]; then vendor/bin/drush sset system.maintenance_mode 1 && vendor/bin/drush cr; fi' || true

case "$DRIVER" in
  mysql|mariadb)
    TGT_USER=$(get_env_val .env.$TGT "$TGT_USER_KEY")
    TGT_PASS=$(get_env_val .env.$TGT "$TGT_PASS_KEY")
    TGT_DB=$(get_env_val .env.$TGT "$TGT_DB_KEY")
    # import using env var for password
    docker exec -i -e MYSQL_PWD="$TGT_PASS" "$TGT_DB_CONTAINER" sh -c "mysql -u\"$TGT_USER\" \"$TGT_DB\"" < "$TMPDIR/db.sql"
    ;;
  postgres)
    TGT_USER=$(get_env_val .env.$TGT "$TGT_USER_KEY")
    TGT_PASS=$(get_env_val .env.$TGT "$TGT_PASS_KEY")
    TGT_DB=$(get_env_val .env.$TGT "$TGT_DB_KEY")
    docker exec -i -e PGPASSWORD="$TGT_PASS" "$TGT_DB_CONTAINER" sh -c "psql -U \"$TGT_USER\" -d \"$TGT_DB\"" < "$TMPDIR/db.sql"
    ;;
esac

echo "Syncing files directory from source drupal-fpm -> target drupal-fpm"
SRC_FPM=infrasight_drupal_fpm
TGT_FPM=infrasight_drupal_fpm

echo "Streaming files from source container to target container (no host temp)..."
# prepare target (backup existing files)
docker exec "$TGT_FPM" sh -c 'cd /var/www/html/web/sites/default && [ -d files ] && mv files files.bak || true && mkdir -p files'
docker exec -i "$SRC_FPM" sh -c 'cd /var/www/html/web/sites/default && tar -czf - files' | docker exec -i "$TGT_FPM" sh -c 'cd /var/www/html/web/sites/default && tar -xzf -'

echo "Attempting post-sync tasks on target (drush)"
docker exec -i "$TGT_FPM" sh -c 'if [ -x vendor/bin/drush ]; then vendor/bin/drush updb -y || true; vendor/bin/drush cim -y || true; vendor/bin/drush cr || true; vendor/bin/drush sset system.maintenance_mode 0 || true; vendor/bin/drush cr || true; fi'

echo "Sync finished. Clean temporary files in $TMPDIR" || true

echo "Done. Review target site and run any environment-specific post-sync steps (clear varnish, run config imports, etc.)."
