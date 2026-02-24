#!/usr/bin/env bash

get_env_val_from_file() {
  local env_file="$1"
  local key="$2"

  awk -F= -v k="$key" '
    $0 ~ "^[[:space:]]*#" { next }
    $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$env_file"
}

resolve_db_targets_from_env_file() {
  local env_file="$1"

  if [ ! -f "$env_file" ]; then
    echo "Env file not found: $env_file" >&2
    return 2
  fi

  DB_DRIVER="$(get_env_val_from_file "$env_file" DB_DRIVER || true)"
  DB_DRIVER="${DB_DRIVER:-mysql}"

  COMPOSE_PROJECT_NAME_RESOLVED="$(get_env_val_from_file "$env_file" COMPOSE_PROJECT_NAME || true)"
  COMPOSE_PROJECT_NAME_RESOLVED="${COMPOSE_PROJECT_NAME_RESOLVED:-$(basename "$PWD")}" 

  case "$DB_DRIVER" in
    pgsql)
      DB_SERVICE="db-postgres"
      DB_VOLUME="${COMPOSE_PROJECT_NAME_RESOLVED}_postgres_data"
      ;;
    mysql)
      DB_SERVICE="db-mysql"
      DB_VOLUME="${COMPOSE_PROJECT_NAME_RESOLVED}_mysql_data"
      ;;
    mariadb)
      DB_SERVICE="db-mariadb"
      DB_VOLUME="${COMPOSE_PROJECT_NAME_RESOLVED}_mariadb_data"
      ;;
    *)
      echo "Unsupported DB_DRIVER in $env_file: '$DB_DRIVER'" >&2
      return 3
      ;;
  esac
}
