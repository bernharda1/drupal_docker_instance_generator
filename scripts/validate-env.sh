#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: validate-env.sh <env-file>

Checks that required keys are present in an .env file.
Returns non-zero if any required key is missing.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage; exit 0
fi

ENV_FILE="${1:-}"
if [ -z "$ENV_FILE" ] || [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  usage
  exit 2
fi

# Required keys for generator + compose
REQUIRED=(
  COMPOSER_PROJECT_NAME
  PROJECT_BASE_PATH
  STACK_ENV
  COMPOSE_PROFILES
)

MISSING=()
for k in "${REQUIRED[@]}"; do
  if ! grep -qE "^[[:space:]]*${k}=" "$ENV_FILE"; then
    MISSING+=("$k")
  fi
done

# Additional warnings
WARN=()
# If env is stag/prod, PUBLIC_DOMAIN should be set
STACK_ENV_VAL=$(awk -F= '/^STACK_ENV=/{gsub(/^[ \\t]+|[ \\t]+$/,"",$2); print $2; exit}' "$ENV_FILE" || true)
if [ "$STACK_ENV_VAL" = "stag" ] || [ "$STACK_ENV_VAL" = "prod" ]; then
  if ! grep -qE "^[[:space:]]*PUBLIC_DOMAIN=" "$ENV_FILE"; then
    WARN+=("PUBLIC_DOMAIN (recommended for stag/prod)")
  fi
fi

if [ ${#MISSING[@]} -ne 0 ]; then
  echo "Missing required .env keys in $ENV_FILE:" >&2
  for m in "${MISSING[@]}"; do echo "  - $m" >&2; done
  exit 3
fi

if [ ${#WARN[@]} -ne 0 ]; then
  echo "Warnings for $ENV_FILE:" >&2
  for w in "${WARN[@]}"; do echo "  - $w" >&2; done
fi

echo "Env validation passed: $ENV_FILE"
exit 0
