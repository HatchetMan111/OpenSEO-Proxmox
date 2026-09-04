# OpenSEO für Proxmox LXC (Community-Script Logik)

Open-Source Alternative zu Semrush und Ahrefs als LXC-Container auf Proxmox VE.
Upstream: https://github.com/every-app/open-seo

## Struktur (community-scripts Stil)

- `ct/open-seo.sh` — läuft auf dem Proxmox-Host (Container erstellen via `build.func`)
- `install/open-seo-install.sh` — läuft im Container (Docker + GHCR-Image deployen)
- `json/open-seo.json` — Metadaten für Website-Generator / unattended Install

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/OpenSEO-Proxmox/main/ct/open-seo.sh)"
```

Unattended:

```bash
var_dataforseo_key="BASE64_LOGIN_PASSWORT" var_port="3001" bash ct/open-seo.sh
```

## Voraussetzungen

- Proxmox VE (LXC, Debian 12 Template, Nesting für Docker)
- DataForSEO API-Key als base64 `login:password`:
  `echo -n 'mail:passwort' | base64`
  Siehe https://github.com/every-app/open-seo/blob/main/docs/DATAFORSEO_API_KEY.md
- Ressourcen: 2 CPU / 4 GB RAM / 12 GB Disk (Erststart baut 1–2 Min)

## Hinweise

- Docker-Modus = `AUTH_MODE=local_noauth` (kein Login) — nur hinter eigenem
  Auth-Reverse-Proxy, Tunnel oder Privatnetz exposen!
- Config: `/opt/open-seo/.env`, Compose: `/opt/open-seo/compose.yaml`
- Update: Update-Modus von `ct/open-seo.sh` (compose pull + up -d)
- Telemetrie Opt-out: `OPENSEO_TELEMETRY_DISABLED=1` in `.env`
