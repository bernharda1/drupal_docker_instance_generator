## Traefik systemd service (docker-compose)

Kurz: Diese Unit startet und verwaltet Traefik via `docker compose` im Verzeichnis `/opt/traefik`.

Files:
- Service unit: [deploy/traefik-docker.service](deploy/traefik-docker.service)

Wichtige Hinweise
- Die Unit nutzt `WorkingDirectory=/opt/traefik`. Passe das Verzeichnis an, falls dein Compose-Setup an einem anderen Ort liegt.
- `ExecStart` führt `docker compose up --no-build --detach` aus. Bei anderen Deploy-Flows (Swarm, plain docker run) ersetze den Befehl.
- Service managed den Compose-Stack, nicht den einzelnen Traefik-Container. Logs via `journalctl -u traefik-docker.service`.

Typische Operationen
```
# Unit kopieren und aktivieren (als root)
sudo cp deploy/traefik-docker.service /etc/systemd/system/traefik-docker.service
sudo systemctl daemon-reload
sudo systemctl enable --now traefik-docker.service

# Service kontrollieren
sudo systemctl status traefik-docker.service
sudo journalctl -u traefik-docker.service --no-pager -n 200

# Compose commands (WorkingDirectory beachten)
cd /opt/traefik
docker compose up --no-build    # Hinweis: Service-Unit startet compose im Vordergrund (kein `-d`), damit systemd den Prozess überwacht
docker compose down
docker compose restart
```

Upgrade / Troubleshooting
- Wenn Compose oder Docker-CLI an einem anderen Pfad liegt, passe `ExecStart`/`ExecStop` in der Unit an.
- Die aktuelle Unit beinhaltet `ExecStartPre`-Prüfungen (Docker verfügbar, Compose-File vorhanden) und startet `docker compose up` im Vordergrund, so dass systemd den Prozess überwachen kann.

Zusätzlich wird nach dem Start ein Healthcheck-Skript im Hintergrund ausgeführt:

- Repo: `deploy/healthcheck-traefik.sh`
- Installiert: `/opt/traefik/healthcheck-traefik.sh` (ausführbar)
- Healthcheck-Log: `/var/log/traefik-health.log`

Das Skript prüft die lokale Traefik-API (z.B. `/ping`) und versucht außerdem, ein TLS-Zertifikat für `projects.infrasight-solutions.com` vom lokalen Traefik zu lesen.
- Wenn du Traefik als Container-Unit (nicht via compose) bevorzugst, erstelle eine Unit mit `ExecStart=/usr/bin/docker run --rm ...` oder verwende Podman.

Sicherheit
- Die Unit führt `docker compose` als Systemdienst aus; sichere `/opt/traefik` und die Compose-Dateien (Zugriffsrechte) entsprechend.

Fragen / nächste Schritte
- Soll ich Healthchecks oder `ExecStartPre`-Validierung hinzufügen?
