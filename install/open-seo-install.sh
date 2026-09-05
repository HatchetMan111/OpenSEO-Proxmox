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
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# --- Pflichtwert: DataForSEO API Key (base64 "login:password") ---
# Nur fragen wenn der Caller (ct-Script / Website-Feld / -s) nichts mitgegeben hat.
if [[ -z "${var_dataforseo_key:-}" ]]; then
  read -rp "${TAB3}DataForSEO API Key (base64 login:password, siehe docs/DATAFORSEO_API_KEY.md): " var_dataforseo_key
fi
if [[ -z "${var_dataforseo_key:-}" ]]; then
  msg_error "DATAFORSEO_API_KEY is required. Abbruch."
  exit 1
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
