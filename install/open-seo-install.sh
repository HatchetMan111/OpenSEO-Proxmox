#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: every-app (upstream) / Community Script Port
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/every-app/open-seo

# Funktionen: normal via build.func (FUNCTIONS_FILE_PATH gesetzt), ersatzweise direkt
# laden, damit das Script auch standalone per pct exec läuft.
if [[ -z "${FUNCTIONS_FILE_PATH:-}" ]]; then
  FUNCTIONS_FILE_PATH="$(curl -fsSL --max-time 30 https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)"
fi
if [[ -z "${FUNCTIONS_FILE_PATH:-}" ]]; then
  echo "Fehler: Funktionsbibliothek (install.func) konnte nicht geladen werden." >&2
  exit 1
fi
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

# Defaults ZUERST: install.func läuft mit set -u, jede ungesetzte Variable
# (direkter pct-exec-Weg ohne export aus dem CT-Script) bricht sonst ab.
# APPLICATION/APP/NSAPP/app/PASSWORD/SSH_* setzt normal build.func (motd_ssh/customize).
export APPLICATION="${APPLICATION:-OpenSEO}"
export APP="${APP:-OpenSEO}"
export NSAPP="${NSAPP:-open-seo}"
export app="${app:-open-seo}"
export PASSWORD="${PASSWORD:-}"
export SSH_AUTHORIZED_KEY="${SSH_AUTHORIZED_KEY:-}"
export SSH_ROOT="${SSH_ROOT:-no}"
var_dataforseo_key="${var_dataforseo_key:-}"
var_port="${var_port:-3001}"
var_allowed_host="${var_allowed_host:-}"
var_openrouter_key="${var_openrouter_key:-}"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# --- DataForSEO API Key: optional beim Install, nachpflegbar ---
# Ohne Key startet die App trotzdem (Upstream-Preflight: nur "warn").
# Key = base64 "login:password" aus dem DataForSEO-Dashboard. Setzbar via:
#   Umgebungsvariable var_dataforseo_key (unattended) oder später in /opt/open-seo/.env
# Nie interaktiv fragen: Das Script muss in einem Durchgang ohne Rückfragen laufen.
if [[ -z "${var_dataforseo_key:-}" ]]; then
  msg_warn "DATAFORSEO_API_KEY ist leer — Web-UI startet trotzdem, SEO-Daten erst nach Nachtragen (siehe Schluss-Hinweis)."
fi
var_port="${var_port:-3001}"
var_allowed_host="${var_allowed_host:-}"
var_openrouter_key="${var_openrouter_key:-}"

msg_info "Installing Dependencies (Docker + Compose)"
$STD apt-get install -y ca-certificates curl gnupg lsb-release
setup_docker
msg_ok "Installed Docker"

msg_info "Deploying OpenSEO (GHCR image)"
mkdir -p /opt/open-seo

# Upstream-compose.yaml nachgebaut (compose.yaml aus dem Repo):
# ghcr.io/every-app/open-seo:latest, AUTH_MODE=local_noauth, Volume open_seo_data -> /app/.wrangler
cat <<EOF >/opt/open-seo/compose.yaml
services:
  open-seo:
    image: \${OPEN_SEO_IMAGE:-ghcr.io/every-app/open-seo:latest}
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - CLOUDFLARE_INCLUDE_PROCESS_ENV=true
      - PORT=\${PORT:-${var_port}}
      - ALLOWED_HOST=\${ALLOWED_HOST:-}
      - AUTH_MODE=local_noauth
      - OPENSEO_TELEMETRY_DISABLED=\${OPENSEO_TELEMETRY_DISABLED:-}
      - DO_NOT_TRACK=\${DO_NOT_TRACK:-}
      - DATAFORSEO_API_KEY=\${DATAFORSEO_API_KEY}
      - OPENROUTER_API_KEY=\${OPENROUTER_API_KEY:-}
      - OPENROUTER_MODEL=\${OPENROUTER_MODEL:-}
      - GOOGLE_CLIENT_ID=\${GOOGLE_CLIENT_ID:-}
      - GOOGLE_CLIENT_SECRET=\${GOOGLE_CLIENT_SECRET:-}
      - BETTER_AUTH_SECRET=\${BETTER_AUTH_SECRET:-}
      - VITE_SHOW_DEVTOOLS=false
    ports:
      - "0.0.0.0:\${PORT:-${var_port}}:\${PORT:-${var_port}}"
    volumes:
      - open_seo_data:/app/.wrangler
volumes:
  open_seo_data:
EOF

# .env — ausdrücklich gesetzte Werte, Rest als Kommentar-Vorlage
cat <<EOF >/opt/open-seo/.env
# OpenSEO self-host env (Docker-Modus, AUTH_MODE=local_noauth)
DATAFORSEO_API_KEY=${var_dataforseo_key}
PORT=${var_port}
ALLOWED_HOST=${var_allowed_host}
OPEN_SEO_IMAGE=ghcr.io/every-app/open-seo:latest
OPENROUTER_API_KEY=${var_openrouter_key}
# Optional:
# OPENROUTER_MODEL=
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=
# BETTER_AUTH_SECRET=ersetze-durch-langen-zufaelligen-secret-mind-32-zeichen
# OPENSEO_TELEMETRY_DISABLED=1  # oder DO_NOT_TRACK=1 zum Deaktivieren des anonymen Heartbeats
EOF
chmod 600 /opt/open-seo/.env

cd /opt/open-seo
$STD docker compose pull
$STD docker compose up -d
msg_ok "Deployed OpenSEO"

msg_info "Waiting for healthcheck (/api/health)"
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${var_port}/api/health" >/dev/null 2>&1; then
    msg_ok "OpenSEO is healthy"
    break
  fi
  # Erster Start baut die App im Container (1-2 Min), HEALTHCHECK start-period 300s
  if [[ "$i" -eq 30 ]]; then
    msg_warn "Noch nicht healthy — folge dem Fortschritt mit: docker compose -f /opt/open-seo/compose.yaml logs -f"
  fi
  sleep 10
done

motd_ssh
customize
cleanup_lxc

# customize() verdrahtet /usr/bin/update fest auf upstream (dort gibt es open-seo nicht).
# Auf unser Repo zeigen, damit der Update-Befehl im Container funktioniert.
echo 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/OpenSEO-Proxmox/main/ct/open-seo.sh)"' >/usr/bin/update
chmod +x /usr/bin/update

# --- Schluss-Zusammenfassung: unübersehbar + mit echtem Erreichbarkeits-Test ---
__ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
__ip="${__ip:-<CT-IP>}"
__url="http://${__ip}:${var_port}"
if curl -fsS --max-time 10 "${__url}/api/health" >/dev/null 2>&1; then
  __ui="ERREICHBAR - im Browser oeffnen"
else
  __ui="NOCH NICHT ERREICHBAR - 1-2 Min warten, dann Seite neu laden"
fi
echo ""
echo -e "${BGN}==============================================================${CL}"
echo -e "${BGN}  OpenSEO Web-UI: ${__url}${CL}"
echo -e "${BGN}  Status: ${__ui}${CL}"
echo -e "${BGN}==============================================================${CL}"
echo -e "${TAB}${TAB}${GN}Kein Login nötig (kein Passwort, kein admin/admin). Einfach öffnen.${CL}"
if [[ -z "${var_dataforseo_key:-}" ]]; then
  echo -e "${TAB}${TAB}${YW}Noch ohne SEO-Daten: DATAFORSEO_API_KEY nachtragen:${CL}"
  echo -e "${TAB}${TAB}  1. Key erzeugen: echo -n 'mail:api-passwort' | base64  (API-Passwort aus dem DataForSEO-Dashboard)"
  echo -e "${TAB}${TAB}  2. In /opt/open-seo/.env bei DATAFORSEO_API_KEY eintragen"
  echo -e "${TAB}${TAB}  3. docker compose -f /opt/open-seo/compose.yaml up -d --force-recreate open-seo"
fi
unset __ip __url __ui
