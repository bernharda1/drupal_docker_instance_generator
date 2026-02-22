#!/usr/bin/env bash
# Setze sinnvolle Dateirechte für ein Drupal-Projekt
# Default: Projekt-Docroot ist ./drupal/web, Webuser www-data:www-data

set -euo pipefail

WWWUSER="www-data"
WWWGROUP="www-data"
# Base Drupal directory (contains web, vendor, recipes)
DRUPAL_DIR="./drupal"
DOCROOT="$DRUPAL_DIR/web"

# Prüfe, ob wir als root laufen (dann sind chown-Operationen möglich)
if [ "$(id -u)" -eq 0 ]; then
  CAN_CHOWN=1
else
  CAN_CHOWN=0
fi
DRYRUN=0
VERBOSE=0

usage(){
  cat <<EOF
Usage: $0 [-p DOCROOT] [-u WWWUSER] [-g WWWGROUP] [-n] [-v]
  -p DOCROOT   Pfad zum Web-Root (default: ./drupal/web)
  -u WWWUSER   Webserver user (default: www-data)
  -g WWWGROUP  Webserver group (default: www-data)
  -n           Dry-run (nur anzeigen, nicht ausführen)
  -v           Verbose
EOF
}

while getopts ":p:u:g:nv" opt; do
  case $opt in
    p) DOCROOT="$OPTARG" ;;
    u) WWWUSER="$OPTARG" ;;
    g) WWWGROUP="$OPTARG" ;;
    n) DRYRUN=1 ;;
    v) VERBOSE=1 ;;
    *) usage; exit 1 ;;
  esac
done

run(){
  if [ "$DRYRUN" -eq 1 ]; then
    echo "+ $*"
  else
    if [ "$VERBOSE" -eq 1 ]; then
      echo "> $*"
    fi
    eval "$@"
  fi
}

if [ ! -d "$DRUPAL_DIR" ]; then
  echo "Drupal-Ordner nicht gefunden: $DRUPAL_DIR"
  exit 2
fi

echo "Setze Berechtigungen für Drupal-Instanz in: $DRUPAL_DIR (user: $WWWUSER:$WWWGROUP)"

# 1) Basisrechte: Verzeichnisse 755, Dateien 644 innerhalb des Web-Roots
if [ -d "$DOCROOT" ]; then
  run "find '$DOCROOT' -type d -print -exec chmod 0755 {} +"
  run "find '$DOCROOT' -type f -print -exec chmod 0644 {} +"
else
  echo "Warnung: Web-Root nicht gefunden: $DOCROOT"
fi

# 2) Wichtige schreibbare Verzeichnisse für Drupal (nur innerhalb des Web-Roots)
WRITABLE=(
  "$DOCROOT/sites/default/files"
  "$DOCROOT/sites/default/private"
  "$DOCROOT/sites/default/tmp"
)

for d in "${WRITABLE[@]}"; do
  if [ -n "$d" ] && [ -e "$d" ]; then
    if [ "$CAN_CHOWN" -eq 1 ]; then
      run "chown -R $WWWUSER:$WWWGROUP '$d'"
    else
      [ "$VERBOSE" -eq 1 ] && echo "Überspringe chown für $d (keine Root-Rechte)"
    fi
    run "chmod -R 2775 '$d'"
    run "find '$d' -type d -exec chmod g+s {} +"
  else
    [ "$VERBOSE" -eq 1 ] && echo "Kein writable-Verzeichnis: $d"
  fi
done

# 3) Optional: chown für den gesamten Docroot (Hinweis nur)

if [ "$CAN_CHOWN" -eq 1 ]; then
  if [ "$DRYRUN" -eq 0 ]; then
    echo "Hinweis: chown -R $WWWUSER:$WWWGROUP $DOCROOT wurde nicht automatisch ausgeführt (nur Writable-Ordner geändert)."
  else
    echo "Dry-run: chown für gesamten Docroot wurde nicht ausgeführt."
  fi
else
  echo "Keine Root-Rechte: chown-Operationen wurden übersprungen. Führe bei Bedarf manuell aus: sudo chown -R $WWWUSER:$WWWGROUP $DRUPAL_DIR"
fi

# 4) Vendor-bin ausführbar machen (innerhalb der Drupal-Instanz)
VENDOR_BIN="$DRUPAL_DIR/vendor/bin"
if [ -d "$VENDOR_BIN" ]; then
  run "find '$VENDOR_BIN' -type f -print -exec chmod 0755 {} +"
fi

# 5) Falls in recipes Skripte liegen, nur dort ausführbar setzen
RECIPES_DIR="$DRUPAL_DIR/recipes"
if [ -d "$RECIPES_DIR" ]; then
  run "find '$RECIPES_DIR' -type f -iname '*.sh' -print -exec chmod 0755 {} +"
fi

echo "Fertig. Zusammenfassung:"
if [ "$DRYRUN" -eq 1 ]; then
  echo "Dry-run abgeschlossen. Keine Änderungen vorgenommen."
else
  echo "Dateien: 0644, Verzeichnisse: 0755, writable: 2775 (gesetzt wenn vorhanden) in $DRUPAL_DIR"
fi

exit 0
