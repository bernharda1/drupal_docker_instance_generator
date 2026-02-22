#!/bin/sh
set -eu

COMPOSE_FILE=/opt/traefik/docker-compose.yml
RETRIES=6
SLEEP=2

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "compose file missing: $COMPOSE_FILE" >&2
  exit 2
fi

CID=$(docker compose -f "$COMPOSE_FILE" ps -q traefik 2>/dev/null || true)
if [ -z "$CID" ]; then
  echo "traefik container not running" >&2
  exit 3
fi

i=0
while [ $i -lt $RETRIES ]; do
  if docker exec "$CID" curl -fsS --connect-timeout 3 http://127.0.0.1:8080/ping >/dev/null 2>&1; then
    echo "traefik healthy"
    exit 0
  fi
  if docker exec "$CID" curl -fsS --connect-timeout 3 http://127.0.0.1:8080/ >/dev/null 2>&1; then
    echo "traefik http ok"
    exit 0
  fi
  i=$((i+1))
  sleep $SLEEP
done

echo "traefik healthcheck failed after ${RETRIES} attempts" >&2
docker logs --tail 50 "$CID" >&2 || true
exit 4

# Additional TLS check: verify Traefik serves a cert for our wildcard domain
DOMAIN="projects.infrasight-solutions.com"
TMPCERT=$(mktemp /tmp/traefik-cert.XXXXXX.pem)
if openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" -showcerts </dev/null 2>/tmp/ssl.out | awk '/-----BEGIN CERTIFICATE-----/{flag=1} flag{print} /-----END CERTIFICATE-----/{print; flag=0}' > "$TMPCERT" 2>/dev/null; then
  if openssl x509 -noout -text -in "$TMPCERT" | grep -q "DNS:$DOMAIN"; then
    echo "TLS cert for $DOMAIN present"
    rm -f "$TMPCERT"
    exit 0
  else
    echo "TLS cert does not contain DNS:$DOMAIN" >&2
    openssl x509 -noout -text -in "$TMPCERT" >&2 || true
    rm -f "$TMPCERT"
    exit 5
  fi
else
  echo "failed to fetch TLS cert from 127.0.0.1:443" >&2
  rm -f "$TMPCERT" || true
  exit 6
fi
