#!/usr/bin/env bash
set -euo pipefail

# Install systemd timer for boot-time git pull + kit update.

UPDATE_MODE="${UPDATE_MODE:-0}"

if [ -f /etc/default/wyse-ndi-kit ]; then
  # shellcheck disable=SC1091
  . /etc/default/wyse-ndi-kit
fi

AUTO_UPDATE="${WYSE_NDI_KIT_AUTO_UPDATE:-1}"
BOOT_DELAY="${WYSE_NDI_KIT_AUTO_UPDATE_BOOT_DELAY_SEC:-180}"
RANDOM_DELAY="${WYSE_NDI_KIT_AUTO_UPDATE_RANDOM_DELAY_SEC:-120}"

log() { printf '== %s ==\n' "$*"; }

log "Installing wyse-ndi-kit auto-update units"

sudo tee /etc/systemd/system/wyse-ndi-kit-auto-update.service >/dev/null <<'EOF'
[Unit]
Description=Wyse NDI kit git pull and apply update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wyse-ndi-auto-update
StandardOutput=journal
StandardError=journal
EOF

sudo tee /etc/systemd/system/wyse-ndi-kit-auto-update.timer >/dev/null <<EOF
[Unit]
Description=Check Wyse NDI kit for updates after boot

[Timer]
OnBootSec=${BOOT_DELAY}
RandomizedDelaySec=${RANDOM_DELAY}
Persistent=true
Unit=wyse-ndi-kit-auto-update.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload

if [ "$AUTO_UPDATE" = "1" ]; then
  sudo systemctl enable wyse-ndi-kit-auto-update.timer
  if [ "$UPDATE_MODE" = "1" ]; then
    log "Timer enabled (runs after boot; see systemctl status wyse-ndi-kit-auto-update.timer)"
  else
    sudo systemctl start wyse-ndi-kit-auto-update.timer || true
  fi
else
  sudo systemctl disable wyse-ndi-kit-auto-update.timer 2>/dev/null || true
  log "Auto-update disabled in /etc/default/wyse-ndi-kit — timer not enabled"
fi

log "Log file: /var/log/wyse-ndi-kit-auto-update.log"
