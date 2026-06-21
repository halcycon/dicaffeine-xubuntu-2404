#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-${TARGET_USER:-$USER}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_UID="$(id -u "$TARGET_USER")"
UPDATE_MODE="${UPDATE_MODE:-0}"
KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$TARGET_USER" = "root" ] && [ -z "${SUDO_USER:-}" ]; then
  echo "Run this through sudo from the normal desktop user, not as root directly."
  exit 1
fi

if [ "$UPDATE_MODE" != "1" ] || ! command -v conky >/dev/null 2>&1; then
  echo "== Installing desktop info overlay packages =="
  sudo apt update
  sudo apt install --no-install-recommends -y \
    conky-all \
    qrencode \
    fonts-dejavu-core \
    iproute2
else
  echo "== Update mode: conky already installed; refreshing overlay configs =="
fi

UPDATE_MODE="$UPDATE_MODE" TARGET_USER="$TARGET_USER" bash "${KIT_ROOT}/scripts/install-common-helpers.sh"

QR_DIR="/var/lib/wyse-ndi"
/usr/local/bin/wyse-ensure-qr-dir 2>/dev/null || \
  sudo /usr/local/bin/wyse-ensure-qr-dir 2>/dev/null || \
  sudo install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$QR_DIR"
sudo rm -f "${QR_DIR}"/*.meta 2>/dev/null || true

echo "== Creating Conky configs =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/conky"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/conky/wyse-vban.conf" >/dev/null <<'EOF'
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
    own_window_title = 'Wyse VBAN Status',
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
    color2 = 'FFD866',

    minimum_width = 500,
    minimum_height = 220,
    maximum_width = 500,

    gap_x = 20,
    gap_y = 250,

    border_inner_margin = 14,
    border_outer_margin = 0,
};

conky.text = [[
${execi 10 /usr/local/bin/wyse-vban-update-qr >/dev/null 2>&1}
${voffset 134}${goto 390}${font DejaVu Sans:size=8}${color1}${execi 10 /usr/local/bin/wyse-vban-qr-caption}${color}${font}
${voffset -134}${goto 0}
${font DejaVu Sans:bold:size=13}${color2}VBAN AudioBox${color}${font}
${font DejaVu Sans Mono:size=10}${execi 5 /usr/local/bin/wyse-vban-status}${font}
${image /tmp/vban-audiobox-qr.png -p 390,34 -s 96x96}
]];
EOF

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

    minimum_width = 500,
    minimum_height = 220,
    maximum_width = 500,

    gap_x = 20,
    gap_y = 20,

    border_inner_margin = 14,
    border_outer_margin = 0,
};

conky.text = [[
${execi 10 /usr/local/bin/wyse-ndi-update-qr >/dev/null 2>&1}
${voffset 134}${goto 390}${font DejaVu Sans:size=8}${color1}${execi 10 /usr/local/bin/wyse-ndi-qr-caption}${color}${font}
${voffset -134}${goto 0}
${font DejaVu Sans:bold:size=13}${color2}Dicaffeine Receiver${color}${font}
${font DejaVu Sans Mono:size=10}${execi 10 /usr/local/bin/wyse-ndi-status}${font}
${image /tmp/dicaffeine-webui-qr.png -p 390,34 -s 96x96}
]];
EOF

echo "== Creating Xfce autostart entries =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/autostart"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/autostart/wyse-vban-status.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Wyse VBAN Status Overlay
Comment=Show VBAN stream and manager details on desktop
Exec=sh -c 'sleep 4; /usr/bin/conky -c "$TARGET_HOME/.config/conky/wyse-vban.conf"'
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/autostart/wyse-ndi-status.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Wyse NDI Status Overlay
Comment=Show IP addresses and Dicaffeine QR code on desktop
Exec=sh -c 'sleep 4; /usr/bin/conky -c "$TARGET_HOME/.config/conky/wyse-ndi.conf"'
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "== Starting overlays in current session if available =="

sudo -u "$TARGET_USER" env \
  DISPLAY=:0 \
  XAUTHORITY="$TARGET_HOME/.Xauthority" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  /usr/local/bin/wyse-ndi-update-qr || true

if command -v wyse-vban-update-qr >/dev/null 2>&1; then
  sudo -u "$TARGET_USER" env \
    DISPLAY=:0 \
    XAUTHORITY="$TARGET_HOME/.Xauthority" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
    /usr/local/bin/wyse-vban-update-qr || true
fi

pkill -u "$TARGET_USER" -f 'conky.*wyse-vban.conf' 2>/dev/null || true
pkill -u "$TARGET_USER" -f 'conky.*wyse-ndi.conf' 2>/dev/null || true

sudo -u "$TARGET_USER" env \
  DISPLAY=:0 \
  XAUTHORITY="$TARGET_HOME/.Xauthority" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  nohup conky -c "$TARGET_HOME/.config/conky/wyse-vban.conf" \
  >/tmp/wyse-vban-conky.log 2>&1 &

sudo -u "$TARGET_USER" env \
  DISPLAY=:0 \
  XAUTHORITY="$TARGET_HOME/.Xauthority" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  nohup conky -c "$TARGET_HOME/.config/conky/wyse-ndi.conf" \
  >/tmp/wyse-ndi-conky.log 2>&1 &

echo
echo "Desktop info overlays installed."
echo
echo "Configs:"
echo "  $TARGET_HOME/.config/conky/wyse-vban.conf"
echo "  $TARGET_HOME/.config/conky/wyse-ndi.conf"
echo
echo "Helpers:"
echo "  /usr/local/bin/wyse-vban-status"
echo "  /usr/local/bin/wyse-vban-update-qr"
echo "  /usr/local/bin/wyse-vban-qr-caption"
echo "  /usr/local/bin/wyse-ndi-status"
echo "  /usr/local/bin/wyse-ndi-update-qr"
echo "  /usr/local/bin/wyse-ndi-qr-caption"
