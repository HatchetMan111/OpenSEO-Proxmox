#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: every-app (upstream) / Community Script Port
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/every-app/open-seo

source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")

APP="OpenSEO"
var_tags="${var_tags:-seo;analytics;marketing}"
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
