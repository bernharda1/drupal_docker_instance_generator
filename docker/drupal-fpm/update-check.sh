#!/usr/bin/env bash
set -euo pipefail

policy="${1:-check}"
target="${2:-system}"

log() {
  printf '[update-check] %s\n' "$1"
}

if ! command -v apt-get >/dev/null 2>&1; then
  log "Kein apt-get verfügbar, Update-Check übersprungen."
  exit 0
fi

log "Policy=${policy}, Target=${target}"
apt-get update -qq

case "${policy}" in
  check)
    apt list --upgradable 2>/dev/null || true
    ;;
  upgrade)
    if [[ "${target}" == "php" ]]; then
      mapfile -t pkgs < <(apt list --upgradable 2>/dev/null | awk -F/ '/^php/ {print $1}')
      if [[ ${#pkgs[@]} -gt 0 ]]; then
        log "Aktualisiere PHP-Pakete: ${pkgs[*]}"
        apt-get install -y --only-upgrade "${pkgs[@]}"
      else
        log "Keine apt-PHP-Pakete aktualisierbar (PHP im offiziellen Drupal-Image wird i.d.R. aus Source bereitgestellt)."
      fi
    else
      log "Führe System-Upgrade aus"
      apt-get upgrade -y
    fi
    ;;
  *)
    log "Unbekannte Policy '${policy}', überspringe."
    ;;
esac
