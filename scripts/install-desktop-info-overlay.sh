#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"

if [ "$TARGET_USER" = "root" ]; then
  echo "Run this through sudo from the normal desktop user, not as root directly."
  exit 1
fi

echo "== Installing desktop info overlay packages =="

sudo apt update
sudo apt install --no-install-recommends -y \
  conky-all \
  qrencode \
  fonts-dejavu-core \
  iproute2

echo "== Installing status helper =="

sudo tee /usr/local/bin/wyse-ndi-status >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SETUP_STATE="/run/wyse-wifi-setup/state"

if [ -f "$SETUP_STATE" ]; then
  # shellcheck disable=SC1090
  . "$SETUP_STATE" || true
fi

if [ "${WYSE_WIFI_SETUP_ACTIVE:-0}" = "1" ]; then
  echo "Wi-Fi Setup Mode"
  echo "SSID: ${WYSE_WIFI_SETUP_SSID:-Dicaffeine-Setup}"
  echo "Pass: ${WYSE_WIFI_SETUP_PASSPHRASE:-dicaffeine}"
  echo "Open: http://192.168.42.1/"
  echo
  echo "Scan QR to join setup Wi-Fi."
  echo "If no page opens, browse to"
  echo "http://192.168.42.1/"
  exit 0
fi

primary_ip="$(
  ip -4 route get 1.1.1.1 2>/dev/null |
    awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
)"

if [ -z "${primary_ip:-}" ]; then
  primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [ -n "${primary_ip:-}" ]; then
  web_url="http://${primary_ip}/"
else
  web_url="No network"
fi

host="$(hostname -s)"

wifi_ssid="$(
  nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null |
    awk -F: '$1=="yes" {print $2; exit}'
)"

if [ -z "${wifi_ssid:-}" ]; then
  wifi_ssid="not connected"
fi

dicaffeine_state="$(
  systemctl --user is-active dicaffeine 2>/dev/null || true
)"

if [ -z "$dicaffeine_state" ]; then
  dicaffeine_state="unknown"
fi

echo "Host: ${host}"
echo "Web:  ${web_url}"
echo "WiFi: ${wifi_ssid}"
echo "Dicaffeine: ${dicaffeine_state}"
echo
echo "IP addresses:"

ip -o -4 addr show scope global 2>/dev/null |
  awk '{
    split($4, a, "/");
    iface=$2;

    # Keep the overlay compact so it does not collide with the QR code.
    short=iface;
    if (short ~ /^en/) short="eth";
    else if (short ~ /^wl/) short="wifi";
    else if (short ~ /^tailscale/) short="ts";
    else if (short ~ /^docker/) short="dock";
    else if (short ~ /^br-/) short="br";
    else if (length(short) > 8) short=substr(short,1,8);

    printf "  %-6s %s\n", short ":", a[1]
  }'

if ! ip -o -4 addr show scope global 2>/dev/null | grep -q .; then
  echo "  none"
fi
EOF

sudo chmod +x /usr/local/bin/wyse-ndi-status

echo "== Installing QR helper =="

sudo tee /usr/local/bin/wyse-ndi-update-qr >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

QR_FILE="/tmp/dicaffeine-webui-qr.png"
URL_FILE="/tmp/dicaffeine-webui-url.txt"
SETUP_STATE="/run/wyse-wifi-setup/state"

setup_ssid="Dicaffeine-Setup"
setup_passphrase="dicaffeine"

mode="normal"

if [ -f "$SETUP_STATE" ]; then
  # shellcheck disable=SC1090
  . "$SETUP_STATE" || true
fi

if [ "${WYSE_WIFI_SETUP_ACTIVE:-0}" = "1" ]; then
  mode="setup"
fi

if [ "$mode" = "setup" ]; then
  qr_payload="WIFI:T:WPA;S:${WYSE_WIFI_SETUP_SSID:-$setup_ssid};P:${WYSE_WIFI_SETUP_PASSPHRASE:-$setup_passphrase};;"
  display_target="SETUP_WIFI:${WYSE_WIFI_SETUP_SSID:-$setup_ssid}"
else
  primary_ip="$(
    ip -4 route get 1.1.1.1 2>/dev/null |
      awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
  )"

  if [ -z "${primary_ip:-}" ]; then
    primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  if [ -n "${primary_ip:-}" ]; then
    qr_payload="http://${primary_ip}/"
    display_target="$qr_payload"
  else
    qr_payload="http://$(hostname -s).local/"
    display_target="$qr_payload"
  fi
fi

old_target=""
if [ -f "$URL_FILE" ]; then
  old_target="$(cat "$URL_FILE" 2>/dev/null || true)"
fi

if [ "$display_target" != "$old_target" ] || [ ! -s "$QR_FILE" ]; then
  printf '%s\n' "$display_target" > "$URL_FILE"
  qrencode -o "$QR_FILE" -s 5 -m 2 "$qr_payload"
fi
EOF

sudo chmod +x /usr/local/bin/wyse-ndi-update-qr

echo "== Creating Conky config =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/conky"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/conky/wyse-ndi.conf" >/dev/null <<'EOF'
conky.config = {
    alignment = 'bottom_right',
    background = true,
    update_interval = 5,
    double_buffer = true,
    no_buffers = true,

    use_xft = true,
    font = 'DejaVu Sans Mono:size=10',

    own_window = true,
    own_window_class = 'Conky',
    own_window_title = 'Wyse NDI Status',
    own_window_type = 'dock',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_argb_visual = true,
    own_window_argb_value = 175,
    own_window_colour = '000000',

    draw_shades = false,
    draw_outline = false,
    draw_borders = false,

    default_color = 'FFFFFF',
    color1 = '9CDCFE',
    color2 = 'A6E22E',

    minimum_width = 430,
    minimum_height = 180,
    maximum_width = 430,

    gap_x = 20,
    gap_y = 20,

    border_inner_margin = 14,
    border_outer_margin = 0,
};

conky.text = [[
${execi 10 /usr/local/bin/wyse-ndi-update-qr >/dev/null 2>&1}
${font DejaVu Sans:bold:size=13}${color2}Dicaffeine Receiver${color}${font}
${execi 10 /usr/local/bin/wyse-ndi-status}
${image /tmp/dicaffeine-webui-qr.png -p 300,42 -s 110x110}
]];
EOF

echo "== Creating Xfce autostart entry =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/autostart"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/autostart/wyse-ndi-status.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Wyse NDI Status Overlay
Comment=Show IP addresses and Dicaffeine QR code on desktop
Exec=sh -c 'sleep 4; /usr/bin/conky -c "$TARGET_HOME/.config/conky/wyse-ndi.conf"'
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "== Starting overlay in current session if available =="

sudo -u "$TARGET_USER" env \
  DISPLAY=:0 \
  XAUTHORITY="$TARGET_HOME/.Xauthority" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  /usr/local/bin/wyse-ndi-update-qr || true

pkill -u "$TARGET_USER" -f 'conky.*wyse-ndi.conf' 2>/dev/null || true

sudo -u "$TARGET_USER" env \
  DISPLAY=:0 \
  XAUTHORITY="$TARGET_HOME/.Xauthority" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  nohup conky -c "$TARGET_HOME/.config/conky/wyse-ndi.conf" \
  >/tmp/wyse-ndi-conky.log 2>&1 &

echo
echo "Desktop info overlay installed."
echo
echo "Config:"
echo "  $TARGET_HOME/.config/conky/wyse-ndi.conf"
echo
echo "Helpers:"
echo "  /usr/local/bin/wyse-ndi-status"
echo "  /usr/local/bin/wyse-ndi-update-qr"
echo
echo "Autostart:"
echo "  $TARGET_HOME/.config/autostart/wyse-ndi-status.desktop"
echo
echo "QR output:"
echo "  /tmp/dicaffeine-webui-qr.png"
