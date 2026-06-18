#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ "$TARGET_USER" = "root" ]; then
  echo "Run this as the normal desktop user with sudo available, not directly as root."
  exit 1
fi

cd "$(dirname "$0")"

find_required_deb_by_package() {
  local package="$1"
  local matches=()

  while IFS= read -r -d '' deb; do
    local deb_package
    deb_package="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"

    if [ "$deb_package" = "$package" ]; then
      matches+=("$deb")
    fi
  done < <(find ./debs -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)

  if [ "${#matches[@]}" -eq 0 ]; then
    echo "ERROR: no .deb found for required package: $package" >&2
    exit 1
  fi

  if [ "${#matches[@]}" -gt 1 ]; then
    echo "ERROR: multiple .debs found for package: $package" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  fi

  printf '%s\n' "${matches[0]}"
}

find_optional_deb_by_package() {
  local package="$1"
  local matches=()

  while IFS= read -r -d '' deb; do
    local deb_package
    deb_package="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"

    if [ "$deb_package" = "$package" ]; then
      matches+=("$deb")
    fi
  done < <(find ./debs -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)

  if [ "${#matches[@]}" -gt 1 ]; then
    echo "ERROR: multiple .debs found for optional package: $package" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  fi

  if [ "${#matches[@]}" -eq 1 ]; then
    printf '%s\n' "${matches[0]}"
  fi
}

DEB_COMPAT="$(find_required_deb_by_package dicaffeine-compat-dummy)"
DEB_PISTACHE="$(find_required_deb_by_package libpistache0)"
DEB_YURI2="$(find_required_deb_by_package yuri2)"
DEB_DICAFFEINE="$(find_required_deb_by_package dicaffeine)"
DEB_NDI="$(find_optional_deb_by_package ndi)"

echo "Using package files:"
echo "  compat:     $DEB_COMPAT"
echo "  pistache:   $DEB_PISTACHE"
echo "  yuri2:      $DEB_YURI2"
echo "  dicaffeine: $DEB_DICAFFEINE"

if [ -n "${DEB_NDI:-}" ]; then
  echo "  ndi:        $DEB_NDI"
else
  echo "  ndi:        not present; will install from NDI SDK download"
fi

echo "== Installing base/runtime packages =="

sudo apt update

sudo apt install --no-install-recommends -y \
  curl \
  ca-certificates \
  openssh-server \
  avahi-daemon \
  libavahi-common3 \
  libavahi-client3 \
  libcap2-bin \
  libssl3 \
  libgl1 \
  libegl1 \
  libglu1-mesa \
  libavcodec60 \
  libavformat60 \
  libavutil58 \
  libswscale7 \
  libjsoncpp25 \
  libsdl2-2.0-0 \
  libsdl1.2debian \
  libboost-python1.83.0 \
  libboost-system1.83.0 \
  libboost-filesystem1.83.0 \
  libboost-program-options1.83.0 \
  libboost-thread1.83.0 \
  libboost-chrono1.83.0 \
  libboost-date-time1.83.0 \
  libboost-regex1.83.0 \
  libboost-iostreams1.83.0 \
  x11-xserver-utils \
  jq \
  python3

echo "== Installing NDI runtime =="

if [ -n "${DEB_NDI:-}" ]; then
  echo "Installing NDI from local package: $DEB_NDI"
  sudo apt install --no-install-recommends -y "$DEB_NDI"
else
  echo "No local NDI .deb found; installing from NDI SDK download."

  if [ ! -x ./scripts/install-ndi6-sdk.sh ]; then
    echo "ERROR: ./scripts/install-ndi6-sdk.sh is missing or not executable." >&2
    echo "Either place an NDI .deb in ./debs, or add scripts/install-ndi6-sdk.sh." >&2
    exit 1
  fi

  ./scripts/install-ndi6-sdk.sh --yes
fi

echo "== Installing Dicaffeine/Yuri packages =="

sudo apt install --no-install-recommends -y \
  "$DEB_COMPAT" \
  "$DEB_PISTACHE" \
  "$DEB_YURI2" \
  "$DEB_DICAFFEINE"

sudo apt-mark manual \
  dicaffeine \
  yuri2 \
  ndi \
  libpistache0 \
  dicaffeine-compat-dummy \
  openssh-server \
  avahi-daemon \
  x11-xserver-utils 2>/dev/null || true

echo "== Creating NDI compatibility links =="

REAL_NDI="$(
  sudo find -L /usr/local/lib/ndi /usr/local/lib /usr/lib \
    -type f -name 'libndi.so*' 2>/dev/null | sort -V | tail -1
)"

if [ -z "${REAL_NDI:-}" ]; then
  echo "ERROR: could not find libndi.so after installing NDI package."
  exit 1
fi

sudo mkdir -p /usr/local/lib

sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so
sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so.5
sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so.6

echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/ndi-local.conf >/dev/null
sudo ldconfig

echo "== Installing environment wrapper =="

sudo tee /usr/local/bin/dicaffeine-env >/dev/null <<'EOENV'
#!/usr/bin/env bash
export NDI_PATH=/usr/local/lib/libndi.so
export LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib:${LD_LIBRARY_PATH:-}
exec "$@"
EOENV

sudo chmod +x /usr/local/bin/dicaffeine-env

echo "== Installing SDL2/RGBA32 player wrapper =="

sudo tee /usr/local/bin/dicaffeine-yuri-player >/dev/null <<EOFPLAYER
#!/usr/bin/env bash
set -u

LOG_TAG=dicaffeine-yuri-player
PLAYER_JSON=/etc/dicaffeine/player.json

export DISPLAY="\${DISPLAY:-:0}"
export XAUTHORITY="\${XAUTHORITY:-${TARGET_HOME}/.Xauthority}"
export NDI_PATH=/usr/local/lib/libndi.so
export LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib:\${LD_LIBRARY_PATH:-}

xset s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset -dpms 2>/dev/null || true

SRC="\$(
python3 <<'PY'
import json
import sys
from pathlib import Path

p = Path("/etc/dicaffeine/player.json")

try:
    data = json.loads(p.read_text())
    streams = data.get("streams", [])
    if not streams:
        sys.exit(1)

    name = str(streams[0].get("name", "")).strip()
    if not name:
        sys.exit(1)

    print(name)
except Exception:
    sys.exit(1)
PY
)"

if [ -z "\${SRC:-}" ]; then
  logger -t "\$LOG_TAG" "ERROR: could not read source from \${PLAYER_JSON}"
  exit 1
fi

logger -t "\$LOG_TAG" "Starting SDL2/RGBA32 player for source: \${SRC}"

exec /usr/bin/yuri_simple \\
  "ndi_input[stream=\"\${SRC}\",format=rgba32]" \\
  "convert[format=rgba32]" \\
  "sdl2_window[resolution=1280x720,fullscreen=1]"
EOFPLAYER

sudo chmod +x /usr/local/bin/dicaffeine-yuri-player

echo "== Patching Dicaffeine config =="

sudo mkdir -p /etc/dicaffeine
sudo chown "$TARGET_USER:$TARGET_USER" /etc/dicaffeine

if [ -f /etc/dicaffeine/dserver.json ]; then
  sudo cp /etc/dicaffeine/dserver.json "/etc/dicaffeine/dserver.json.bak.$(date +%Y%m%d-%H%M%S)"
fi

sudo python3 - <<'PY'
import json
from pathlib import Path

p = Path("/etc/dicaffeine/dserver.json")

if p.exists():
    data = json.loads(p.read_text())
else:
    data = {}

data.update({
    "address": "0.0.0.0",
    "auth_config": "/etc/dicaffeine/dauth.json",
    "player_config": "/etc/dicaffeine/player.json",
    "port": 80,
    "simple_api": True,
    "static_dir": "/usr/share/dicaffeine/",
    "yuri_binary": "/usr/local/bin/dicaffeine-yuri-player",
    "yuri_pconfig": "/tmp/yuri_config_player.xml",
    "yuri_pkill": "pkill -9 -f 'yuri_simple.*ndi_input|dicaffeine-yuri-player'",
    "yuri_pre": "DISPLAY=:0 xset s off -dpms",
    "max_framerate": 30,
    "threads": 2,
})

p.write_text(json.dumps(data, indent=4) + "\n")
PY

sudo chown "$TARGET_USER:$TARGET_USER" /etc/dicaffeine/dserver.json
sudo chmod 664 /etc/dicaffeine/dserver.json

echo "== Ensuring auth config exists =="

if [ ! -f /etc/dicaffeine/dauth.json ]; then
  sudo tee /etc/dicaffeine/dauth.json >/dev/null <<'EOAUTH'
{
    "users": []
}
EOAUTH
fi

sudo chown "$TARGET_USER:$TARGET_USER" /etc/dicaffeine/dauth.json
sudo chmod 664 /etc/dicaffeine/dauth.json

echo "== Disabling screen blanking and locking =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/autostart"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.xprofile" >/dev/null <<'EOXP'
#!/usr/bin/env bash
xset s off
xset s noblank
xset -dpms
EOXP

chmod +x "$TARGET_HOME/.xprofile"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/autostart/disable-screen-blanking.desktop" >/dev/null <<'EODSK'
[Desktop Entry]
Type=Application
Name=Disable Screen Blanking
Comment=Disable projector screen blanking
Exec=sh -c 'xset s off; xset s noblank; xset -dpms'
Terminal=false
X-GNOME-Autostart-enabled=true
EODSK

sudo -u "$TARGET_USER" xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false 2>/dev/null || true
sudo -u "$TARGET_USER" xfconf-query -c xfce4-screensaver -p /lock/enabled -n -t bool -s false 2>/dev/null || true
sudo -u "$TARGET_USER" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/presentation-mode -n -t bool -s true 2>/dev/null || true
sudo -u "$TARGET_USER" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0 2>/dev/null || true
sudo -u "$TARGET_USER" xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false 2>/dev/null || true

echo "== Installing optional Dicaffeine boot/wallpaper theme =="

if [ "${INSTALL_DICAFFEINE_THEME:-1}" = "1" ]; then
  if [ -x ./scripts/install-dicaffeine-theme.sh ]; then
    ./scripts/install-dicaffeine-theme.sh
  else
    echo "Theme installer not found; skipping."
  fi
else
  echo "INSTALL_DICAFFEINE_THEME=0 set; skipping theme install."
fi

echo "== Creating helper scripts =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/bin"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/bin/list-ndi-sources.sh" >/dev/null <<'EOLIST'
#!/usr/bin/env bash
export NDI_PATH=/usr/local/lib/libndi.so
export LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib:${LD_LIBRARY_PATH:-}
exec /usr/bin/yuri2 -I ndi_input
EOLIST

sudo -u "$TARGET_USER" chmod +x "$TARGET_HOME/bin/list-ndi-sources.sh"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/bin/play-ndi-manual.sh" >/dev/null <<'EOPLAY'
#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-}"

if [ -z "$SRC" ]; then
  echo "Usage: $0 'EXACT NDI SOURCE NAME'"
  exit 1
fi

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
export NDI_PATH=/usr/local/lib/libndi.so
export LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib:${LD_LIBRARY_PATH:-}

xset s off || true
xset s noblank || true
xset -dpms || true

exec /usr/bin/yuri_simple \
  "ndi_input[stream=\"${SRC}\",format=rgba32]" \
  "convert[format=rgba32]" \
  "sdl2_window[resolution=1280x720,fullscreen=1]"
EOPLAY

sudo -u "$TARGET_USER" chmod +x "$TARGET_HOME/bin/play-ndi-manual.sh"

echo "== Configuring Dicaffeine user service =="

sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.config/systemd/user/dicaffeine.service.d"

sudo -u "$TARGET_USER" tee "$TARGET_HOME/.config/systemd/user/dicaffeine.service.d/override.conf" >/dev/null <<EOFOVR
[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=${TARGET_HOME}/.Xauthority
Environment=NDI_PATH=/usr/local/lib/libndi.so
Environment=LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib
EOFOVR

sudo loginctl enable-linger "$TARGET_USER" || true

sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" systemctl --user daemon-reload || true
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" systemctl --user enable dicaffeine || true
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" systemctl --user restart dicaffeine || true

echo "== Applying Dell Wyse 3040 DMA workaround =="

sudo tee /etc/modprobe.d/wyse-3040-reboot-fix.conf >/dev/null <<'EOF'
# Dell Wyse 3040 Linux reboot/shutdown hang workaround.
# Prevent DesignWare DMA / HSUART DMA modules from loading.
blacklist dw_dmac
blacklist dw_dmac_core
install dw_dmac /bin/true
install dw_dmac_core /bin/true
EOF

sudo update-initramfs -u

echo "== Applying Dell Wyse 3040 reboot method workaround =="

sudo cp /etc/default/grub "/etc/default/grub.bak.reboot-pci.$(date +%Y%m%d-%H%M%S)"

sudo python3 - <<'PY'
from pathlib import Path
import shlex

p = Path("/etc/default/grub")
lines = p.read_text().splitlines()
out = []
seen = False

for line in lines:
    if line.startswith("GRUB_CMDLINE_LINUX_DEFAULT="):
        seen = True
        _, value = line.split("=", 1)

        try:
            words = shlex.split(value.strip())
        except Exception:
            words = []

        # Remove duplicate quiet/splash/vt.handoff and any previous reboot= mode.
        cleaned = []
        for word in words:
            if word.startswith("reboot="):
                continue
            if word not in cleaned:
                cleaned.append(word)

        if "reboot=pci" not in cleaned:
            cleaned.append("reboot=pci")

        out.append('GRUB_CMDLINE_LINUX_DEFAULT="' + " ".join(cleaned) + '"')
    else:
        out.append(line)

if not seen:
    out.append('GRUB_CMDLINE_LINUX_DEFAULT="quiet splash reboot=pci"')

p.write_text("\n".join(out) + "\n")
PY

sudo update-grub

echo "== Installing optional desktop info overlay =="

if [ "${INSTALL_DESKTOP_INFO_OVERLAY:-1}" = "1" ]; then
  if [ -x ./scripts/install-desktop-info-overlay.sh ]; then
    ./scripts/install-desktop-info-overlay.sh
  else
    echo "Desktop info overlay installer not found; skipping."
  fi
else
  echo "INSTALL_DESKTOP_INFO_OVERLAY=0 set; skipping desktop info overlay."
fi

echo "== Installing optional native Wi-Fi setup portal watcher =="

if [ "${INSTALL_WIFI_SETUP_PORTAL:-1}" = "1" ]; then
  if [ -x ./scripts/install-wifi-setup-portal-native.sh ]; then
    ./scripts/install-wifi-setup-portal-native.sh
  else
    echo "Native Wi-Fi setup portal installer not found; skipping."
  fi
else
  echo "INSTALL_WIFI_SETUP_PORTAL=0; skipping Wi-Fi setup portal watcher."
fi

echo "== Final sanity checks =="

sudo ldconfig

ldd /usr/bin/yuri2 | grep "not found" && exit 1 || true
ldd /usr/bin/yuri_simple | grep "not found" && exit 1 || true
ldd /usr/lib/yuri2/yuri2.8_module_ndi.so | grep "not found" && exit 1 || true
ldd /usr/lib/yuri2/yuri2.8_module_sdl2_window.so | grep "not found" && exit 1 || true

echo
echo "Done."
echo
echo "Reboot, then test:"
echo "  ~/bin/list-ndi-sources.sh"
echo
echo "Dicaffeine web UI should be available on:"
echo "  http://<wyse-ip>/"
echo
echo "Manual fallback:"
echo "  ~/bin/play-ndi-manual.sh 'EXACT NDI SOURCE NAME'"
