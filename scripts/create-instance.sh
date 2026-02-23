#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-}"
TARGET_BASE_PATH="${TARGET_BASE_PATH:-}"
STACK_ENV="${STACK_ENV:-}"
COMPOSER_PROJECT_NAME="${COMPOSER_PROJECT_NAME:-}"
PUBLIC_DOMAIN_OVERRIDE="${PUBLIC_DOMAIN_OVERRIDE:-}"
FORCE=0
NO_INPUT=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/create-instance.sh [options]

Erstellt eine neue Drupal-Instanz aus dem Template in drupal_docker_image.
Fehlende Parameter werden interaktiv abgefragt.

Optionen:
  -n <name>       Projektname (z. B. infrasightshop)
  -p <path>       Speicherort/Basispfad (z. B. /home/dev/projects)
  -e <env>        Umgebung: dev | stag | prod
  -c <name>       Composer-Name (z. B. infrasightsolutions/infrasightshop)
  -d <domain>     PUBLIC_DOMAIN Override
  -y              Non-interactive, nutze Defaults oder error bei fehlenden Werten
  -f              Existierendes Zielverzeichnis überschreiben
  -r, --dry-run   Keine Änderungen durchführen, nur ausgeben (Simulation)
  -h              Hilfe anzeigen

Beispiele:
  scripts/create-instance.sh -n shop360 -p /home/dev/projects -e dev
  scripts/create-instance.sh -n shop360 -p /srv/stag -e stag -d shop360-stag.example.com
EOF
}

print_cmd() {
  printf '+ '
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    print_cmd "$@"
    return 0
  fi
  "$@"
}

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

read_env_value() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    return 1
  fi
  awk -F= -v k="$key" '
    $0 ~ "^[[:space:]]*#" { next }
    $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

set_or_add_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    sed -i "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

select_env_file() {
  case "$1" in
    dev) printf '%s' "$TEMPLATE_ROOT/.env.dev" ;;
    stag) printf '%s' "$TEMPLATE_ROOT/.env.stag" ;;
    prod) printf '%s' "$TEMPLATE_ROOT/.env.prod" ;;
    *) return 1 ;;
  esac
}

fallback_base_path_for_env() {
  case "$1" in
    dev) printf '/home/dev/projects' ;;
    stag) printf '/srv/stag' ;;
    prod) printf '/srv/prod' ;;
    *) printf '/home/dev/projects' ;;
  esac
}

while getopts ":n:p:e:c:d:fyhr-:" opt; do
  case "$opt" in
    n) PROJECT_NAME="$(trim "$OPTARG")" ;;
    p) TARGET_BASE_PATH="$(trim "$OPTARG")" ;;
    e) STACK_ENV="$(to_lower "$(trim "$OPTARG")")" ;;
    c) COMPOSER_PROJECT_NAME="$(trim "$OPTARG")" ;;
    d) PUBLIC_DOMAIN_OVERRIDE="$(trim "$OPTARG")" ;;
    f) FORCE=1 ;;
    y) NO_INPUT=1 ;;
    r) DRY_RUN=1 ;;
    -)
      case "${OPTARG}" in
        dry-run) DRY_RUN=1 ;;
        help) usage; exit 0 ;;
        *) echo "Unbekannte Option: --${OPTARG}" >&2; usage; exit 1 ;;
      esac
      ;;
    h) usage; exit 0 ;;
    :) echo "Fehlender Wert für -$OPTARG" >&2; usage; exit 1 ;;
    \?) echo "Unbekannte Option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$STACK_ENV" ]; then
  if [ "$NO_INPUT" -eq 1 ]; then
    echo "Missing required: environment (-e) in non-interactive mode" >&2
    usage; exit 1
  fi
  read -rp "Umgebung (dev/stag/prod): " STACK_ENV
  STACK_ENV="$(to_lower "$(trim "$STACK_ENV")")"
fi

case "$STACK_ENV" in
  dev|stag|prod) ;;
  *) echo "Ungültige Umgebung: $STACK_ENV (erlaubt: dev|stag|prod)" >&2; exit 1 ;;
esac

ENV_SOURCE_FILE="$(select_env_file "$STACK_ENV")"
if [ ! -f "$ENV_SOURCE_FILE" ]; then
  echo "Umgebungsdatei nicht gefunden: $ENV_SOURCE_FILE" >&2
  exit 1
fi

if [ -z "$PROJECT_NAME" ]; then
  if [ "$NO_INPUT" -eq 1 ]; then
    echo "Missing required: project name (-n) in non-interactive mode" >&2
    usage; exit 1
  fi
  read -rp "Projektname: " PROJECT_NAME
  PROJECT_NAME="$(trim "$PROJECT_NAME")"
fi

# Validate project name: disallow slashes and path-traversal
if [[ "$PROJECT_NAME" == *"/"* ]] || [[ "$PROJECT_NAME" == *".."* ]]; then
  echo "Ungültiger Projektname: enthält '/' oder '..'" >&2
  exit 1
fi

# If name contains unsafe chars, propose slugified fallback
if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  SUGGESTION="$(slugify "$PROJECT_NAME")"
  if [ -z "$SUGGESTION" ]; then
    echo "Projektname enthält keine gültigen Zeichen nach Slugify." >&2
    exit 1
  fi
  if [ "$NO_INPUT" -eq 1 ]; then
    PROJECT_NAME="$SUGGESTION"
  else
    read -rp "Projektname enthält ungültige Zeichen. Verwenden: $SUGGESTION ? [Y/n]: " use_sug
    use_sug="$(to_lower "$(trim "$use_sug")")"
    if [ -z "$use_sug" ] || [ "$use_sug" = "y" ] || [ "$use_sug" = "yes" ]; then
      PROJECT_NAME="$SUGGESTION"
    else
      echo "Abbruch durch Nutzer." >&2
      exit 1
    fi
  fi
fi

PROJECT_SLUG="$(slugify "$PROJECT_NAME")"
if [ -z "$PROJECT_SLUG" ]; then
  echo "Projektname enthält keine gültigen Zeichen nach Slugify." >&2
  exit 1
fi

if [ -z "$TARGET_BASE_PATH" ]; then
  TARGET_BASE_PATH="$(read_env_value "$ENV_SOURCE_FILE" "PROJECT_BASE_PATH" || true)"
  if [ -z "$TARGET_BASE_PATH" ]; then
    TARGET_BASE_PATH="$(fallback_base_path_for_env "$STACK_ENV")"
  fi
  read -rp "Speicherort/Basispfad [$TARGET_BASE_PATH]: " input_path
  input_path="$(trim "$input_path")"
  if [ -n "$input_path" ]; then
    TARGET_BASE_PATH="$input_path"
  fi
fi

TARGET_BASE_PATH="$(trim "$TARGET_BASE_PATH")"
if [ -z "$TARGET_BASE_PATH" ]; then
  echo "Basispfad darf nicht leer sein." >&2
  exit 1
fi

DEFAULT_COMPOSER_FROM_ENV="$(read_env_value "$ENV_SOURCE_FILE" "COMPOSER_PROJECT_NAME" || true)"
if [ -z "$COMPOSER_PROJECT_NAME" ]; then
  if [ -n "$DEFAULT_COMPOSER_FROM_ENV" ]; then
    COMPOSER_PROJECT_NAME="$DEFAULT_COMPOSER_FROM_ENV"
  else
    COMPOSER_PROJECT_NAME="infrasightsolutions/${PROJECT_SLUG}"
  fi
  if [ "$NO_INPUT" -eq 0 ]; then
    read -rp "Composer-Name [$COMPOSER_PROJECT_NAME]: " input_composer
    input_composer="$(trim "$input_composer")"
    if [ -n "$input_composer" ]; then
      COMPOSER_PROJECT_NAME="$input_composer"
    fi
  fi
fi

DEFAULT_PUBLIC_DOMAIN="$(read_env_value "$ENV_SOURCE_FILE" "PUBLIC_DOMAIN" || true)"
if [ -z "$PUBLIC_DOMAIN_OVERRIDE" ]; then
  if [ -n "$DEFAULT_PUBLIC_DOMAIN" ]; then
    if [ "$NO_INPUT" -eq 1 ]; then
      PUBLIC_DOMAIN_OVERRIDE="$DEFAULT_PUBLIC_DOMAIN"
    else
      read -rp "PUBLIC_DOMAIN [$DEFAULT_PUBLIC_DOMAIN]: " input_domain
      input_domain="$(trim "$input_domain")"
      if [ -n "$input_domain" ]; then
        PUBLIC_DOMAIN_OVERRIDE="$input_domain"
      else
        PUBLIC_DOMAIN_OVERRIDE="$DEFAULT_PUBLIC_DOMAIN"
      fi
    fi
  else
    if [ "$NO_INPUT" -eq 1 ]; then
      PUBLIC_DOMAIN_OVERRIDE=""
    else
      read -rp "PUBLIC_DOMAIN: " input_domain
      PUBLIC_DOMAIN_OVERRIDE="$(trim "$input_domain")"
    fi
  fi
fi

TARGET_DIR="${TARGET_BASE_PATH%/}/$PROJECT_NAME"

case "$TARGET_DIR" in
  "$TEMPLATE_ROOT"|"$TEMPLATE_ROOT"/*)
    echo "Zielpfad darf nicht innerhalb des Template-Ordners liegen: $TARGET_DIR" >&2
    exit 1
    ;;
esac

if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
  if [ "$FORCE" -ne 1 ]; then
    if [ "$NO_INPUT" -eq 1 ]; then
      echo "Zielordner $TARGET_DIR ist nicht leer. Use -f to overwrite in non-interactive mode." >&2
      exit 1
    fi
    read -rp "Zielordner $TARGET_DIR ist nicht leer. Überschreiben? [y/N]: " confirm
    confirm="$(to_lower "$(trim "$confirm")")"
    if [ "$confirm" != "y" ] && [ "$confirm" != "yes" ]; then
      echo "Abbruch." >&2
      exit 1
    fi
  fi
  run_cmd rm -rf "$TARGET_DIR"
fi

run_cmd mkdir -p "$TARGET_DIR"

# Copy template into target. Prefer rsync to exclude VCS dirs; fallback to cp+rm.
if command -v rsync >/dev/null 2>&1; then
  run_cmd rsync -a --exclude='.git' --exclude='.github' "$TEMPLATE_ROOT/." "$TARGET_DIR/"
else
  run_cmd cp -a "$TEMPLATE_ROOT/." "$TARGET_DIR/"
  run_cmd rm -rf "$TARGET_DIR/.git" "$TARGET_DIR/.github"
fi

# Use environment-specific env file as primary source of truth, since the helper scripts
# expect .env.dev/.env.stag/.env.prod. Also keep .env in sync for convenience.
TARGET_ENV_FILE="$TARGET_DIR/.env.$STACK_ENV"
run_cmd cp "$ENV_SOURCE_FILE" "$TARGET_ENV_FILE"

# Keep .env pointing to the selected environment file.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "+ would link $TARGET_DIR/.env -> .env.$STACK_ENV"
else
  ln -sf ".env.$STACK_ENV" "$TARGET_DIR/.env"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "+ would set STACK_ENV=$STACK_ENV in $TARGET_ENV_FILE"
  echo "+ would set COMPOSER_PROJECT_NAME=$COMPOSER_PROJECT_NAME in $TARGET_ENV_FILE"
else
  set_or_add_env_value "$TARGET_ENV_FILE" "STACK_ENV" "$STACK_ENV"
  set_or_add_env_value "$TARGET_ENV_FILE" "COMPOSER_PROJECT_NAME" "$COMPOSER_PROJECT_NAME"
fi

if [ -n "$PUBLIC_DOMAIN_OVERRIDE" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "+ would set PUBLIC_DOMAIN=$PUBLIC_DOMAIN_OVERRIDE in $TARGET_ENV_FILE"
  else
    set_or_add_env_value "$TARGET_ENV_FILE" "PUBLIC_DOMAIN" "$PUBLIC_DOMAIN_OVERRIDE"
  fi
fi

#  -- Validate generated .env
VALIDATE_SCRIPT="$TEMPLATE_ROOT/scripts/validate-env.sh"
if [ -x "$VALIDATE_SCRIPT" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    print_cmd "$VALIDATE_SCRIPT" "$TARGET_ENV_FILE"
  elif ! "$VALIDATE_SCRIPT" "$TARGET_ENV_FILE"; then
    if [ "$NO_INPUT" -eq 1 ]; then
      echo "Env validation failed and running in non-interactive mode. Aborting." >&2
      exit 1
    fi
    echo "Env validation failed. Öffne $TARGET_ENV_FILE zum Bearbeiten und drücke Enter zum Fortfahren oder Strg-C zum Abbrechen."
    read -r
  fi
else
  echo "Warnung: validate-env.sh nicht ausführbar oder nicht vorhanden; überspringe Env-Validation."
fi

#  -- Docker Compose config check (best-effort)
if command -v docker >/dev/null 2>&1; then
  if docker compose --help >/dev/null 2>&1; then
    echo "Führe 'docker compose config' im Zielordner aus, um Compose-Fehler zu erkennen..."
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "+ (cd $TARGET_DIR && docker compose --env-file .env config)"
    else
      (cd "$TARGET_DIR" && docker compose --env-file .env config) >/dev/null 2>&1 || {
      echo "docker compose config failed for generated instance." >&2
      if [ "$NO_INPUT" -eq 1 ]; then
        echo "Non-interactive: Abbruch." >&2
        exit 1
      else
        echo "Compose config Check fehlgeschlagen. Öffne $TARGET_ENV_FILE oder docker-compose.yml und korrigiere, dann Enter zum Fortfahren." >&2
        read -r
      fi
      }
    fi
  else
    echo "docker compose scheint nicht verfügbar (keine Unterstützung). Überspringe Compose-Check."
  fi
else
  echo "Docker nicht gefunden — überspringe Compose-Check."
fi

TARGET_COMPOSER_JSON="$TARGET_DIR/drupal/composer.json"
TEMPLATE_COMPOSER_JSON="$TEMPLATE_ROOT/drupal/composer.json"

if [ "$DRY_RUN" -eq 1 ]; then
  if [ -f "$TEMPLATE_COMPOSER_JSON" ]; then
    echo "+ would update $TARGET_COMPOSER_JSON: set .name = $COMPOSER_PROJECT_NAME"
  else
    echo "Warnung: Template composer.json nicht gefunden unter $TEMPLATE_COMPOSER_JSON" >&2
  fi
else
  if [ ! -f "$TARGET_COMPOSER_JSON" ]; then
    echo "Warnung: composer.json nicht gefunden unter $TARGET_COMPOSER_JSON" >&2
  else
    # Update composer.json safely: prefer jq, fallback to perl replacement with proper escaping
    if command -v jq >/dev/null 2>&1; then
      tmpfile=$(mktemp)
      jq --arg name "$COMPOSER_PROJECT_NAME" '.name = $name' "$TARGET_COMPOSER_JSON" > "$tmpfile" && mv "$tmpfile" "$TARGET_COMPOSER_JSON"
    else
      # Escape double quotes and backslashes for perl
      esc=$(printf '%s' "$COMPOSER_PROJECT_NAME" | perl -pe 's/([\\"\\\\])/\\$1/g')
      perl -0777 -pe "s/\"name\"\s*:\s*\"[^\"]*\"/\"name\": \"$esc\"/s" -i "$TARGET_COMPOSER_JSON"
    fi
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry-run: Keine Änderungen durchgeführt (Simulation)."
else
  echo "Instanz erfolgreich erstellt."
fi
echo "  Projekt      : $PROJECT_NAME"
echo "  Umgebung     : $STACK_ENV"
echo "  Zielpfad     : $TARGET_DIR"
echo "  .env Quelle  : $(basename "$ENV_SOURCE_FILE")"
echo "  Composer Name: $COMPOSER_PROJECT_NAME"
if [ -n "$PUBLIC_DOMAIN_OVERRIDE" ]; then
  echo "  PUBLIC_DOMAIN: $PUBLIC_DOMAIN_OVERRIDE"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Nächste Schritte (nur Hinweis, da dry-run):"
else
  echo "Nächste Schritte:"
fi
echo "  cd $TARGET_DIR"
echo "  scripts/set-permissions.sh -n -v"
echo "  scripts/up-${STACK_ENV}.sh"
