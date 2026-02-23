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

get_env_value() {
  local key="$1"
  local raw

  raw="$(awk -F= -v k="$key" '
    $0 ~ "^[[:space:]]*#" { next }
    $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$ENV_FILE" || true)"

  raw="${raw%\"}"
  raw="${raw#\"}"
  raw="${raw%\'}"
  raw="${raw#\'}"
  printf '%s' "$raw"
}

public_domain_is_valid() {
  local domain="$1"
  if [ -z "$domain" ]; then
    return 0
  fi
  [[ "$domain" != *"://"* && "$domain" != */* && "$domain" != *" "* ]]
}

tcp_port_is_valid() {
  local port="$1"
  if [ -z "$port" ]; then
    return 0
  fi
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# Required keys for generator + compose
REQUIRED=(
  COMPOSER_PROJECT_NAME
  PROJECT_BASE_PATH
  CONTAINER_PREFIX
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
STACK_ENV_VAL="$(get_env_value "STACK_ENV")"
if [ "$STACK_ENV_VAL" = "stag" ] || [ "$STACK_ENV_VAL" = "prod" ]; then
  if ! grep -qE "^[[:space:]]*PUBLIC_DOMAIN=" "$ENV_FILE"; then
    WARN+=("PUBLIC_DOMAIN (recommended for stag/prod)")
  fi
fi

TRAEFIK_PREFIX_VAL="$(get_env_value "TRAEFIK_PREFIX")"
if [ -z "$TRAEFIK_PREFIX_VAL" ]; then
  WARN+=("TRAEFIK_PREFIX (recommended for stable Traefik router naming)")
fi

ERRORS=()
PUBLIC_DOMAIN_VAL="$(get_env_value "PUBLIC_DOMAIN")"
if ! public_domain_is_valid "$PUBLIC_DOMAIN_VAL"; then
  ERRORS+=("PUBLIC_DOMAIN must be a hostname without scheme/path/spaces (current: '$PUBLIC_DOMAIN_VAL')")
fi

REVERSE_PROXY_HOST_PORT_VAL="$(get_env_value "REVERSE_PROXY_HOST_PORT")"
if ! tcp_port_is_valid "$REVERSE_PROXY_HOST_PORT_VAL"; then
  ERRORS+=("REVERSE_PROXY_HOST_PORT must be a valid TCP port 1-65535 (current: '$REVERSE_PROXY_HOST_PORT_VAL')")
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

if [ ${#ERRORS[@]} -ne 0 ]; then
  echo "Invalid .env values in $ENV_FILE:" >&2
  for e in "${ERRORS[@]}"; do echo "  - $e" >&2; done
  exit 4
fi

echo "Env validation passed: $ENV_FILE"
exit 0
