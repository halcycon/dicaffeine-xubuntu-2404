#!/usr/bin/env bash
set -euo pipefail

SETUP_SSID="${SETUP_SSID:-Dicaffeine-Setup}"
SETUP_PASSPHRASE="${SETUP_PASSPHRASE:-dicaffeine}"

echo "== Installing Wi-Fi setup portal dependencies =="

sudo apt update
sudo apt install --no-install-recommends -y \
  network-manager \
  iw \
  qrencode \
  curl \
  ca-certificates

echo "== Checking for wifi-connect =="

if ! command -v wifi-connect >/dev/null 2>&1; then
  echo
  echo "wifi-connect is not installed yet."
  echo
  echo "Install balena wifi-connect separately, then rerun this script."
  echo "Expected binary:"
  echo "  /usr/local/bin/wifi-connect"
  echo
  echo "The repo can include a helper later to download a pinned release."
  exit 1
fi

echo "== Installing Wi-Fi setup check script =="

sudo tee /usr/local/bin/wyse-wifi-setup-check >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SETUP_SSID="${SETUP_SSID:-Dicaffeine-Setup}"
SETUP_PASSPHRASE="${SETUP_PASSPHRASE:-dicaffeine}"
STATE_DIR="/run/wyse-wifi-setup"
STATE_FILE="${STATE_DIR}/state"

mkdir -p "$STATE_DIR"

wifi_iface="$(
  nmcli -t -f DEVICE,TYPE device status |
    awk -F: '$2=="wifi" && $1 != "" {print $1; exit}'
)"

wired_has_ip=false
wifi_has_normal_ip=false

while IFS=: read -r dev type state connection; do
  case "$type" in
    ethernet)
      if ip -4 addr show dev "$dev" scope global 2>/dev/null | grep -q 'inet '; then
        wired_has_ip=true
      fi
      ;;
    wifi)
      # Treat Wi-Fi setup AP as setup mode, not normal connectivity.
      if [ "$connection" != "$SETUP_SSID" ] && [ "$connection" != "Hotspot" ]; then
        if ip -4 addr show dev "$dev" scope global 2>/dev/null | grep -q 'inet '; then
          wifi_has_normal_ip=true
        fi
      fi
      ;;
  esac
done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status)

if [ "$wired_has_ip" = true ] || [ "$wifi_has_normal_ip" = true ]; then
  rm -f "$STATE_FILE"

  if systemctl is-active --quiet wyse-wifi-connect.service; then
    systemctl stop wyse-wifi-connect.service || true
  fi

  exit 0
fi

if [ -z "${wifi_iface:-}" ]; then
  cat > "$STATE_FILE" <<EOFSTATE
WYSE_WIFI_SETUP_ACTIVE=0
WYSE_WIFI_SETUP_ERROR='No Wi-Fi adapter found'
EOFSTATE
  exit 0
fi

if ! iw list 2>/dev/null | grep -q '^[[:space:]]*\* AP$'; then
  cat > "$STATE_FILE" <<EOFSTATE
WYSE_WIFI_SETUP_ACTIVE=0
WYSE_WIFI_SETUP_ERROR='Wi-Fi adapter does not support AP mode'
EOFSTATE
  exit 0
fi

cat > "$STATE_FILE" <<EOFSTATE
WYSE_WIFI_SETUP_ACTIVE=1
WYSE_WIFI_SETUP_SSID='$SETUP_SSID'
WYSE_WIFI_SETUP_PASSPHRASE='$SETUP_PASSPHRASE'
WYSE_WIFI_SETUP_IFACE='$wifi_iface'
EOFSTATE

if ! systemctl is-active --quiet wyse-wifi-connect.service; then
  systemctl start wyse-wifi-connect.service
fi
EOF

sudo chmod +x /usr/local/bin/wyse-wifi-setup-check

echo "== Installing wifi-connect systemd service =="

sudo tee /etc/systemd/system/wyse-wifi-connect.service >/dev/null <<EOF
[Unit]
Description=Wyse Wi-Fi setup captive portal
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=simple
Environment=SETUP_SSID=${SETUP_SSID}
Environment=SETUP_PASSPHRASE=${SETUP_PASSPHRASE}
ExecStartPre=/bin/mkdir -p /run/wyse-wifi-setup
ExecStartPre=/bin/sh -c 'printf "WYSE_WIFI_SETUP_ACTIVE=1\nWYSE_WIFI_SETUP_SSID=%s\nWYSE_WIFI_SETUP_PASSPHRASE=%s\n" "\$SETUP_SSID" "\$SETUP_PASSPHRASE" > /run/wyse-wifi-setup/state'
ExecStart=/usr/local/bin/wifi-connect -s ${SETUP_SSID} -p ${SETUP_PASSPHRASE} -g 192.168.42.1 -o 80
ExecStopPost=/bin/rm -f /run/wyse-wifi-setup/state
Restart=no

[Install]
WantedBy=multi-user.target
EOF

echo "== Installing periodic setup checker =="

sudo tee /etc/systemd/system/wyse-wifi-setup-check.service >/dev/null <<'EOF'
[Unit]
Description=Check whether Wyse Wi-Fi setup captive portal is needed
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wyse-wifi-setup-check
EOF

sudo tee /etc/systemd/system/wyse-wifi-setup-check.timer >/dev/null <<'EOF'
[Unit]
Description=Periodically check whether Wi-Fi setup captive portal is needed

[Timer]
OnBootSec=20
OnUnitActiveSec=30
AccuracySec=5
Unit=wyse-wifi-setup-check.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now wyse-wifi-setup-check.timer

echo
echo "Wi-Fi setup portal watcher installed."
echo
echo "Current check result:"
sudo /usr/local/bin/wyse-wifi-setup-check || true
cat /run/wyse-wifi-setup/state 2>/dev/null || echo "No setup state active."
