#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-dev}"
override_domain="${2:-}"

case "$target" in
  dev)  env_file=".env.dev" ;;
  stag) env_file=".env.stag" ;;
  prod) env_file=".env.prod" ;;
  *)
    if [[ -f "$target" ]]; then
      env_file="$target"
    else
      echo "Usage: scripts/check-https.sh [dev|stag|prod|/path/to/env] [optional-domain]" >&2
      exit 1
    fi
    ;;
esac

if [[ ! -f "$env_file" ]]; then
  echo "Env file not found: $env_file" >&2
  exit 1
fi

domain="${override_domain}"
if [[ -z "$domain" ]]; then
  domain="$(grep -E '^PUBLIC_DOMAIN=' "$env_file" | tail -n1 | cut -d'=' -f2-)"
fi

if [[ -z "$domain" ]]; then
  echo "PUBLIC_DOMAIN not found in $env_file and no override provided." >&2
  exit 1
fi

# remove optional surrounding quotes
case "$domain" in
  \"*\") domain="${domain#\"}"; domain="${domain%\"}" ;;
  \'*\') domain="${domain#\'}"; domain="${domain%\'}" ;;
esac

url="https://${domain}"

echo "[check-https] env=$env_file domain=$domain"

headers_file="$(mktemp)"
trap 'rm -f "$headers_file"' EXIT

if ! curl -sS -I --max-time 20 "$url" > "$headers_file"; then
  echo "[check-https] direct request failed, retry via local Traefik resolve (127.0.0.1)" >&2
  curl -sS -I --max-time 20 --resolve "${domain}:443:127.0.0.1" "$url" > "$headers_file"
fi

metrics="$(curl -sS -o /dev/null --max-time 20 -w 'http_code=%{http_code} tls_verify=%{ssl_verify_result} http_version=%{http_version} remote_ip=%{remote_ip}\n' "$url" || true)"
if [[ -z "$metrics" ]]; then
  metrics="$(curl -sS -o /dev/null --max-time 20 --resolve "${domain}:443:127.0.0.1" -w 'http_code=%{http_code} tls_verify=%{ssl_verify_result} http_version=%{http_version} remote_ip=%{remote_ip}\n' "$url")"
fi

echo "$metrics"

echo "--- response headers ---"
grep -Ei '^(HTTP/|server:|location:|strict-transport-security:|alt-svc:|x-forwarded-proto:|content-type:)' "$headers_file" || cat "$headers_file"

echo "--- result ---"
if echo "$metrics" | grep -q 'http_code=2\|http_code=3'; then
  echo "HTTPS reachable for ${domain}."
else
  echo "HTTPS check returned non-2xx/3xx status for ${domain}." >&2
  exit 2
fi
