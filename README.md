# Drupal 11.3 Container-Stack (PHP 8.4 FPM, official `drupal` base)

Dieses Setup baut ein eigenes Drupal-Image **auf Basis des offiziellen `drupal`-Containers** und stellt Services per Compose-Profil bereit:

- Webserver wählbar: `web-nginx`, `web-apache`, `web-ols`
- Reverse Proxy: `reverse-proxy` (NGINX)
- Datenbank wählbar: `db-mysql`, `db-mariadb`, `db-postgres`
- Cache wählbar: `cache-redis`, `cache-varnish`
- Zusatztools: `phpmyadmin`, `mailpit`, `tools` (`composer`, `drush`, `node`)

## Starten

Optional zuerst ENV-Konfiguration übernehmen:

```bash
cp .env.example .env
```

## Neue Instanz aus Template erstellen

Das Template kann direkt als neue Projektinstanz für `dev`, `stag` oder `prod` erzeugt werden:

```bash
scripts/create-instance.sh -n <projektname> -p <zielpfad> -e <dev|stag|prod>
```

Beispiel:

```bash
scripts/create-instance.sh -n shop360 -p /home/dev/projects -e dev
```

Wenn Werte fehlen, fragt das Skript assistierend nach (Projektname, Pfad, Umgebung, Domain, Composer-Name).

Zusätzliche Optionen:

```bash
# Composer-Projektname für drupal/composer.json direkt setzen
scripts/create-instance.sh -n shop360 -p /srv/stag -e stag -c infrasightsolutions/shop360

# PUBLIC_DOMAIN direkt setzen
scripts/create-instance.sh -n shop360 -p /srv/prod -e prod -d www.shop360.example.com
```

Hinweis: Der Composer-Name wird aus `COMPOSER_PROJECT_NAME` der jeweiligen `.env.<env>` gelesen und in `drupal/composer.json` als `name` eingetragen.
Der Standard-Zielpfad wird aus `PROJECT_BASE_PATH` der jeweiligen `.env.<env>` gelesen.

`create-instance.sh` setzt außerdem `PUBLIC_DOMAIN` direkt in die Server-Konfigurationen:
- `config/nginx/web-nginx.conf` (`server_name`)
- `config/apache/httpd.conf` (`ServerName`)
- `config/openlitespeed/httpd_config.conf` (`serverName`, `map`, `virtualHost`)
- `config/openlitespeed/vhconf.conf` (`vhDomain`)

Wenn `COMPOSE_PROFILES` das Profil `reverse-proxy` enthält, setzt der Generator `UPSTREAM_HOST` automatisch passend zum aktiven Webprofil:
- `web-ols` → `web-openlitespeed`
- `web-apache` → `web-apache`
- sonst → `web-nginx`

### Preflight-Checkliste vor `create-instance.sh`

- `STACK_ENV` korrekt (`dev`, `stag`, `prod`)
- `PUBLIC_DOMAIN` als Hostname ohne `http(s)://` und ohne Pfad
- `REVERSE_PROXY_HOST_PORT` als numerischer Port (`1..65535`)
- Zielpfad beschreibbar und Zielordner entweder leer oder Aufruf mit `-f`
- Optional vorab prüfen mit `scripts/validate-env.sh .env.<env>`

## Drush/Composer ohne `docker exec`

Im Repo gibt es Wrapper unter `bin/`, die dir das `docker compose exec ...` abnehmen (ähnlich vom Gefühl wie bei Lando):

```bash
bin/composer install
bin/drush status
bin/drush cr
```

Die Wrapper sind `sudo`-kompatibel und verwenden bei Bedarf automatisch `SUDO_UID`/`SUDO_GID`. Falls der Composer-Cache einmal mit falschem Owner angelegt wurde, hilft:

```bash
sudo chown -R $(id -u):$(id -g) .cache
```

Wenn du willst, dass du im Projektordner einfach `composer`/`drush` tippen kannst, kannst du `bin/` temporär in deinen `PATH` nehmen:

```bash
export PATH="$PWD/bin:$PATH"
```

Oder direkt mit fertigen Umgebungsdateien starten:

```bash
docker compose --env-file .env.dev up -d --build
docker compose --env-file .env.stag up -d --build
docker compose --env-file .env.prod up -d --build
```

### Troubleshooting (Instanz-Generator)

- `Ungültige Umgebung`: nur `dev`, `stag`, `prod` sind erlaubt.
- Zielordner nicht leer: mit `-f` überschreiben oder anderen Projektnamen/Pfad wählen.
- Rechtefehler bei `/srv/stag` oder `/srv/prod`: Skript mit einem erlaubten Benutzer ausführen oder Pfad per `-p` auf einen beschreibbaren Ort setzen.
- Falscher Standard-Zielpfad: `PROJECT_BASE_PATH` in `.env.dev`, `.env.stag`, `.env.prod` anpassen.
- Falscher Composer-Name: `COMPOSER_PROJECT_NAME` in `.env.<env>` setzen oder beim Aufruf mit `-c` überschreiben.

#### Env-Validierung (`scripts/validate-env.sh`)

Der Generator ruft die Env-Validierung automatisch auf. Du kannst sie auch manuell ausführen:

```bash
scripts/validate-env.sh .env.dev
scripts/validate-env.sh .env.stag
scripts/validate-env.sh .env.prod
```

Geprüft werden u. a.:

- Pflicht-Keys: `COMPOSER_PROJECT_NAME`, `PROJECT_BASE_PATH`, `CONTAINER_PREFIX`, `STACK_ENV`, `COMPOSE_PROFILES`
- `PUBLIC_DOMAIN`: muss Hostname ohne Schema/Pfad/Leerzeichen sein
- `REVERSE_PROXY_HOST_PORT`: muss TCP-Port im Bereich `1..65535` sein
- Empfehlung: `TRAEFIK_PREFIX` setzen für stabile Traefik-Router-Namen

Exit-Codes:

- `0`: Validierung erfolgreich
- `2`: Env-Datei fehlt oder ist nicht lesbar
- `3`: Pflicht-Keys fehlen
- `4`: Ungültige Env-Werte (z. B. Domain/Port)

Häufige Fehlermeldungen und schnelle Fixes:

- `PUBLIC_DOMAIN must be a hostname ...`
	- Setze `PUBLIC_DOMAIN` ohne Schema/Pfad, z. B. `PUBLIC_DOMAIN=shop.example.com`
- `REVERSE_PROXY_HOST_PORT must be a valid TCP port 1-65535`
	- Setze einen numerischen Port im gültigen Bereich, z. B. `REVERSE_PROXY_HOST_PORT=8088`
- `Missing required .env keys ...`
	- Fehlende Keys aus `.env.example` oder der passenden `.env.<env>` ergänzen

Oder über Hilfsskripte:

```bash
scripts/up-dev.sh
scripts/up-stag.sh
scripts/up-prod.sh
```

Mit optionalem IPv6-Override-Modus:

```bash
scripts/up-stag.sh ipv6
scripts/up-stag.sh ipv6-rp
```

Stoppen je Umgebung:

```bash
scripts/down-dev.sh
scripts/down-stag.sh
scripts/down-prod.sh
```

Mit Volume-/Orphan-Bereinigung:

```bash
scripts/down-stag.sh purge
```

Logs je Umgebung:

```bash
scripts/logs-dev.sh
scripts/logs-stag.sh
scripts/logs-prod.sh
```

Logs für einzelnen Service:

```bash
scripts/logs-stag.sh web-nginx
```

Dev-DB (MySQL) zurücksetzen (Achtung: Datenverlust in DEV-DB):

```bash
scripts/reset-dev-db.sh
```

Staging-/Production-DB zurücksetzen (Achtung: Datenverlust, doppelte Sicherheitsabfrage):

```bash
scripts/reset-stag-db.sh
scripts/reset-prod-db.sh
```

Status je Umgebung:

```bash
scripts/status-dev.sh
scripts/status-stag.sh
scripts/status-prod.sh
```

## COMPOSE-Profiles

Beachte: Services werden nur gestartet, wenn ihr Profil in `COMPOSE_PROFILES` der verwendeten `.env` enthalten ist. Beispiele:

- `fpm` — PHP-FPM-Services (z. B. `drupal-fpm`, `bedrock-fpm`).
- `phpmyadmin`, `mailpit` — UI-Tools; starten nur, wenn diese Profile in `COMPOSE_PROFILES` stehen.

Starten (Beispiel):

```bash
docker compose --env-file .env.dev up -d --build
```

Ändern: Passe `COMPOSE_PROFILES` in `.env.dev`, `.env.stag` oder `.env.prod` an, oder verwende bei Bedarf `--profile` beim `docker compose`-Aufruf.

Status für einzelnen Service:

```bash
scripts/status-prod.sh web-nginx
```

phpMyAdmin und Mailpit UI Zugriff:

- Port-basiert (DEV): `http://localhost:8081` (phpMyAdmin) und `http://localhost:8025` (Mailpit UI)
- Domain-basiert via Traefik: `PHPMYADMIN_DOMAIN` und `MAILPIT_DOMAIN` (TLS + Middleware)
- SMTP für Mailpit bleibt auf `MAILPIT_SMTP_HOST_PORT` (Default `1025`)
- Wenn `TRAEFIK_SECURITY_MIDDLEWARES=dev-vpn-only@file` gesetzt ist, ist Domainzugriff außerhalb des VPN erwartbar `403`.
- Optional kann für nur diese UIs `TRAEFIK_UI_SECURITY_MIDDLEWARES` separat gesetzt werden.

Hinweis: Domain-, Port- und IP-Bindings werden aus den jeweiligen `.env`-Dateien gelesen (`PUBLIC_DOMAIN`, `PHPMYADMIN_DOMAIN`, `MAILPIT_DOMAIN`, `PUBLIC_BIND_ADDRESS`, `PUBLIC_BIND_ADDRESS_V4`, `*_HOST_PORT`).

HTTPS/SSL-Check je Umgebung:

```bash
scripts/check-https-dev.sh
scripts/check-https-stag.sh
scripts/check-https-prod.sh
```

Direkt über Hauptskript (mit optionaler Domain-Override):

```bash
scripts/check-https.sh stag
scripts/check-https.sh prod www.example.com
```

Projektpfade je Umgebung:

- DEV: `/home/dev/projects/<project>`
- STAG: `/srv/stag/<project>`
- PROD: `/srv/prod/<project>`

Wichtig: `docker compose` immer im jeweiligen Projektordner ausführen, damit relative Volumes (`./drupal`, `./config`) korrekt aufgelöst werden.

Service-Auswahl erfolgt primär über `.env` (`COMPOSE_PROFILES`):

- Webserver genau **einen** wählen: `web-nginx` oder `web-apache` oder `web-ols`
- Datenbank genau **einen** wählen: `db-mysql` oder `db-mariadb` oder `db-postgres`
- Cache optional wählen: `cache-redis` und/oder `cache-varnish`
- Reverse-Proxy nur bei Bedarf: `reverse-proxy`
- Zusatzdienste optional: `phpmyadmin`, `mailpit`, `tools`

Dann reicht:

```bash
docker compose up -d --build
```

Alternativ ohne `.env` direkt per CLI-Profile:

```bash
docker compose --profile web-nginx --profile reverse-proxy --profile tools up -d --build
```

## Netzwerkmodell (Best Practice mit `dev_net`/`stag_net`/`prod_net`)

- `app_net` ist intern (`internal: true`) für FPM ↔ Web ↔ Tools
- `edge_net` ist extern und wird über `.env` auf bestehende Umgebung gemappt:
	- Dev: `EDGE_NETWORK_NAME=dev_net`
	- Staging: `EDGE_NETWORK_NAME=stag_net`
	- Prod: `EDGE_NETWORK_NAME=prod_net`
- `proxy` ist extern für Traefik-Docker-Provider (`TRAEFIK_DOCKER_NETWORK=proxy`)

Falls Netze noch nicht existieren:

```bash
docker network create dev_net
docker network create stag_net
docker network create prod_net
```

Empfohlene `.env`-Beispiele:

```bash
# DEV
COMPOSE_PROFILES=web-ols,db-mysql,cache-redis,phpmyadmin,tools
EDGE_NETWORK_NAME=dev_net
UPSTREAM_HOST=web-openlitespeed
DRUPAL_DB_HOST=db-mysql

# STAGING
COMPOSE_PROFILES=web-nginx,reverse-proxy,db-mysql,cache-redis,tools
EDGE_NETWORK_NAME=stag_net
UPSTREAM_HOST=web-nginx
DRUPAL_DB_HOST=db-mysql

# PROD (Beispiel ohne internen Reverse-Proxy)
COMPOSE_PROFILES=web-nginx,db-postgres,cache-redis,tools
EDGE_NETWORK_NAME=prod_net
DRUPAL_DB_DRIVER=pgsql
DRUPAL_DB_HOST=db-postgres
DRUPAL_DB_PORT=5432
```

Best Practice: `phpmyadmin` nur mit `db-mysql`/`db-mariadb` nutzen; für `db-postgres` stattdessen pgAdmin in einem separaten Profil ergänzen.

## Hostname / Domain / HTTP(S) / IPv6

- Domain je Umgebung über `.env`: `PUBLIC_DOMAIN` (z. B. `stag.example.com`, `www.example.com`)
- Öffentlich gebundene Ports IPv6-first über `PUBLIC_BIND_ADDRESS` (Default `[::]`)
- Traefik Labels sind auf Webservern vorkonfiguriert (HTTP→HTTPS Redirect + TLS Router)
- HTTP/2 und HTTP/3 werden in Traefik primär über EntryPoint-Konfiguration aktiviert; Compose liefert die Router/TLS-Bindings.

### Let's Encrypt (Best Practice)

- Für Dev-Projekte als Subdomains unter `projects.infrasight-solutions.com` verwende `TRAEFIK_CERTRESOLVER=le-dns`.
- Setze pro Projekt eine eindeutige Domain, z. B. `PUBLIC_DOMAIN=myproject.projects.infrasight-solutions.com`.
- Für STAG/PROD kann `PUBLIC_DOMAIN` eine beliebige öffentliche Domain sein (z. B. `stag.example.com`, `www.example.com`).
- Starte genau **einen** Webserver-Profiltyp gleichzeitig (`web-nginx` oder `web-apache` oder `web-ols`), um konkurrierende Router für dieselbe Domain zu vermeiden.
- Für Dev-Zugriff bleibt zusätzlich `TRAEFIK_SECURITY_MIDDLEWARES=dev-vpn-only@file` aktiv.

Voraussetzungen für Zertifikatsausstellung:

- Domain DNS zeigt auf den Traefik-Host (A/AAAA je Setup).
- Der in Traefik konfigurierte Resolver-Name entspricht `TRAEFIK_CERTRESOLVER` (hier standardmäßig `le-dns`).
- Bei DNS-01 müssen die DNS-Provider-Credentials in der zentralen Traefik-Umgebung vorhanden sein.

Hinweis zu Trusted Hosts:

- Standardmäßig werden Trusted Hosts aus `PUBLIC_DOMAIN` abgeleitet (via `docker-compose.yml` Default).
- `DRUPAL_TRUSTED_HOST_PATTERNS` nur setzen, wenn mehrere Domains/Patterns benötigt werden.

Konfigurationscheck:

```bash
docker compose --profile web-nginx config | grep -E "Host\(|tls\.certresolver|middlewares"
```

### Statische Container-IPv6 (optional, z. B. STAG/PROD)

Wenn Web-Container eine feste IPv6 im externen Netz (`stag_net`, `prod_net`) benötigen, ist das **optional** über ein Override gelöst:

```bash
docker compose -f docker-compose.yml -f docker-compose.ipv6.yml up -d --build
```

In `.env` setzen:

```bash
EDGE_NETWORK_NAME=stag_net
WEB_IPV6_ADDRESS=2a0a:4cc0:0:2d05:1300::10
```

Für PROD entsprechend:

```bash
EDGE_NETWORK_NAME=prod_net
WEB_IPV6_ADDRESS=2a0a:4cc0:0:2d05:1200::10
```

Ohne Override-Datei werden IPs wie bisher dynamisch vergeben (Best Practice für DEV).

#### Reverse-Proxy als primärer öffentlicher IPv6-Endpunkt

Wenn `reverse-proxy` aktiv ist, kann die primäre öffentliche IPv6 auf dem Reverse-Proxy liegen:

```bash
docker compose -f docker-compose.yml -f docker-compose.ipv6.reverse-proxy.yml up -d --build
```

Beispiel `.env`:

```bash
EDGE_NETWORK_NAME=stag_net
WEB_IPV6_ADDRESS=2a0a:4cc0:0:2d05:1300::10
WEB_BACKEND_IPV6_ADDRESS=2a0a:4cc0:0:2d05:1300::11
```

Damit erhält `reverse-proxy` die primäre IPv6 (`WEB_IPV6_ADDRESS`), der eigentliche Web-Container eine separate Backend-IPv6 im selben `edge_net`.

#### phpMyAdmin IPv6 nur wenn aktiviert

`PHPMYADMIN_IPV6_ADDRESS` wird nur wirksam, wenn Profil `phpmyadmin` aktiv ist und ein IPv6-Override geladen wird.

Empfehlung:

- `dev`: `TRAEFIK_SECURITY_MIDDLEWARES=dev-vpn-only@file` (Public Domain nur via VPN erreichbar)
- `stag`: `TRAEFIK_SECURITY_MIDDLEWARES=staging-auth@file`
- `prod`: leere oder produktive Security-Middleware je Bedarf

Wichtig: Für DEV muss die Domain (z. B. `dev.infrasight-solutions.com`) auf Traefik zeigen, aber der Zugriff wird durch `dev-vpn-only@file` auf VPN-Quellnetze begrenzt.

## Resource Limits & Schreibrechte

- Für **alle** Services sind `mem_limit` und `cpus` per `.env` einstellbar.
- Drupal-Code ist in den Webserver-Containern read-only gemountet; im `drupal-fpm` read-write, damit Drupal-Dateioperationen und Unter-Mounts zuverlässig funktionieren.
- Schreibbar sind nur notwendige Pfade per Named Volumes:
	- `web/sites/default/files`
	- `web/sites/default/private`
	- `/tmp/drupal`
- Rechte werden beim FPM-Start gesetzt über:
	- `DRUPAL_WRITABLE_UID`
	- `DRUPAL_WRITABLE_GID`
	- `DRUPAL_WRITABLE_DIR_MODE`
	- `DRUPAL_WRITABLE_FILE_MODE`

## Composer / Drupal-Installation

Drupal wird **nicht** out-of-the-box installiert. Installation erfolgt via Composer:

```bash
docker compose --profile tools run --rm composer install
```

Drush nutzen:

```bash
docker compose --profile tools up -d drush
docker compose exec drush vendor/bin/drush status
docker compose exec drush vendor/bin/drush cr
```

Node nutzen:

```bash
docker compose --profile tools up -d node
docker compose exec node npm ci
docker compose exec node npm run build
```

## Update-Check / Update beim Container-Start

Pro Service konfigurierbar über ENV in der `docker-compose.yml`:

- `UPDATE_POLICY=off|check|upgrade`
- `UPDATE_TARGET=system|php`

Beispiele:

- `FPM_UPDATE_POLICY=check` → listet verfügbare Updates beim Start
- `FPM_UPDATE_POLICY=upgrade` + `FPM_UPDATE_TARGET=system` → führt System-Upgrade beim Start aus

Hinweis: Für echte PHP-Sicherheitsupdates im offiziellen Drupal-Image ist in der Praxis meist **Image-Rebuild + Redeploy** der saubere Weg.

## Wichtige Konfigurationsdateien

- `docker/drupal-fpm/Dockerfile`
- `docker/drupal-fpm/container-entrypoint.sh`
- `docker/drupal-fpm/update-check.sh`
- `config/php/php.ini`
- `config/nginx/web-nginx.conf`
- `config/apache/httpd.conf`
- `config/openlitespeed/httpd_config.conf`
- `config/openlitespeed/vhconf.conf`
- `config/reverse-proxy/reverse-proxy.conf.template`

## Docker Hub Build & Push

```bash
docker build -f docker/drupal-fpm/Dockerfile -t <dockerhub-user>/drupal11-fpm:11.3-php8.4 .
docker login
docker push <dockerhub-user>/drupal11-fpm:11.3-php8.4
```
