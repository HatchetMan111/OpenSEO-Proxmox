#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: every-app (upstream) / Community Script Port
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/every-app/open-seo

# build.func laden: lokaler Checkout oder Mirrors (fail-loud statt halb zu laufen).
# Hintergrund: ProxmoxVED gibt es auf raw.githubusercontent.com nicht (404),
# kanonisch ist git.community-scripts.org, der alte ProxmoxVE-Mirror lebt noch.
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" ]]; then
  source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func"
else
  __build_tmp="$(mktemp)"
  __build_urls=(
    "${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}/misc/build.func"
    "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func"
  )
  __loaded=0
  for __url in "${__build_urls[@]}"; do
    if curl -fsSL --max-time 30 "$__url" -o "$__build_tmp" 2>/dev/null \
      && [[ -s "$__build_tmp" ]] && grep -q "build_container" "$__build_tmp"; then
      source "$__build_tmp" && __loaded=1 && break
    fi
  done
  rm -f "$__build_tmp"
  unset __build_tmp __build_urls __url
  if [[ "$__loaded" != 1 ]] || ! declare -F header_info >/dev/null 2>&1; then
    echo "Fehler: build.func konnte von keinem Mirror geladen werden (Internet/DNS auf dem Proxmox-Host pruefen)." >&2
    exit 1
  fi
  unset __loaded
fi

APP="OpenSEO"
var_tags="${var_tags:-seo;analytics;marketing}"

# build.func holt das Install-Script fest von upstream:
#   https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/open-seo-install.sh
# Dort existiert es nicht (eigenes Repo) -> curl -f liefert 404, bash -c "" läuft leer durch.
# Deshalb exakt DIESE eine URL auf unser Repo umleiten. Alle anderen curl-Aufrufe
# (build.func, install.func, tools.func, Docker-Keys, GHCR ...) laufen unverändert durch.
OPEN_SEO_INSTALL_URL="https://raw.githubusercontent.com/HatchetMan111/OpenSEO-Proxmox/main/install/open-seo-install.sh"
curl() {
  local a rerouted=()
  for a in "$@"; do
    if [[ "$a" == "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/open-seo-install.sh" ]]; then
      echo ">>> open-seo: install-script reroute -> eigenes Repo" >&2
      rerouted+=("$OPEN_SEO_INSTALL_URL")
    else
      rerouted+=("$a")
    fi
  done
  command curl "${rerouted[@]}"
}
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# Unattended-install fähige Werte — ohne export kommen sie nie im Container an.
# DATAFORSEO_API_KEY ist Pflicht (base64 "login:password", siehe docs/DATAFORSEO_API_KEY.md).
export var_dataforseo_key="${var_dataforseo_key:-}"
export var_port="${var_port:-3001}"
export var_allowed_host="${var_allowed_host:-}"
export var_openrouter_key="${var_openrouter_key:-}"

echo ">>> OpenSEO CT-Installer rev5 (mit install-reroute). Fehlt diese Zeile, läuft eine alte Datei aus dem CDN-Cache." >&2
header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/open-seo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} (Docker image pull)"
  # Upstream-Image, kein GitHub-Release-Tarball -> kein check_for_gh_release/fetch_and_deploy möglich.
  # Update = neues GHCR-Image ziehen + neu erstellen. .env + Volume bleiben erhalten.
  if $STD docker compose -f /opt/open-seo/compose.yaml pull; then
    $STD docker compose -f /opt/open-seo/compose.yaml up -d
    $STD docker image prune -f
    msg_ok "Updated successfully!"
  else
    msg_error "Pull failed — old container left running."
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${BGN}${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:${var_port:-3001}${CL}"
echo -e "${TAB}${TAB}${GN}OpenSEO läuft mit AUTH_MODE=local_noauth (kein Login).${CL}"
echo -e "${TAB}${TAB}${GN}Nur hinter eigenem Auth-Reverse-Proxy / Tunnel / Privatnetz exposen!${CL}"
echo -e "${TAB}${TAB}${GN}DataForSEO-Key: in /opt/open-seo/.env als DATAFORSEO_API_KEY (base64 login:password).${CL}"
