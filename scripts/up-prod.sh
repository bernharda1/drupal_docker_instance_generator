#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-default}"

case "$mode" in
  default)
    docker compose --env-file .env.prod up -d --build
    ;;
  ipv6)
    docker compose --env-file .env.prod -f docker-compose.yml -f docker-compose.ipv6.yml up -d --build
    ;;
  ipv6-rp)
    docker compose --env-file .env.prod -f docker-compose.yml -f docker-compose.ipv6.reverse-proxy.yml up -d --build
    ;;
  *)
    echo "Usage: scripts/up-prod.sh [default|ipv6|ipv6-rp]" >&2
    exit 1
    ;;
esac
