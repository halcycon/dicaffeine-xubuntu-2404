#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ "$TARGET_USER" = "root" ]; then
  echo "Run this through sudo from the normal desktop user, not as root directly."
  exit 1
fi

TMPDIR="$(mktemp -d /tmp/dicaffeine-theme.XXXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "== Installing Plymouth and theme tools =="

sudo apt update
sudo apt install --no-install-recommends -y \
  git \
  plymouth \
  plymouth-themes \
  initramfs-tools \
  x11-xserver-utils

echo "== Downloading upstream Dicaffeine theme assets =="

git clone --depth=1 --filter=blob:none --sparse \
  https://github.com/melnijir/Dicaffeine.git \
  "$TMPDIR/Dicaffeine"

git -C "$TMPDIR/Dicaffeine" sparse-checkout set \
  dicaffeine-theme/usr/share/plymouth/themes/dicaffeine

SRC="$TMPDIR/Dicaffeine/dicaffeine-theme/usr/share/plymouth/themes/dicaffeine"
DEST="/usr/share/plymouth/themes/dicaffeine"

if [ ! -f "$SRC/dicaffeine.plymouth" ] || [ ! -f "$SRC/dicaffeine.script" ]; then
  echo "ERROR: Dicaffeine Plymouth theme files were not found after checkout." >&2
  exit 1
fi

echo "== Installing Dicaffeine Plymouth theme =="

sudo install -d -m 0755 "$DEST"
sudo install -m 0644 "$SRC/background.png" "$DEST/background.png"
sudo install -m 0644 "$SRC/logo.png" "$DEST/logo.png"
sudo install -m 0644 "$SRC/dicaffeine.plymouth" "$DEST/dicaffeine.plymouth"
sudo install -m 0644 "$SRC/dicaffeine.script" "$DEST/dicaffeine.script"

echo "== Setting Plymouth default theme =="

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  sudo plymouth-set-default-theme -R dicaffeine
else
  sudo update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth \
    default.plymouth \
    "$DEST/dicaffeine.plymouth" \
    100

  sudo update-alternatives --set \
    default.plymouth \
    "$DEST/dicaffeine.plymouth"

  sudo update-initramfs -u
fi

echo "== Ensuring GRUB uses quiet splash =="

sudo cp /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d-%H%M%S)"

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
        value = value.strip()

        try:
            words = shlex.split(value)
        except Exception:
            words = []

        for token in ["quiet", "splash"]:
            if token not in words:
                words.append(token)

        out.append('GRUB_CMDLINE_LINUX_DEFAULT="' + " ".join(words) + '"')
    else:
        out.append(line)

if not seen:
    out.append('GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"')

p.write_text("\n".join(out) + "\n")
PY

sudo update-grub

echo "== Installing Dicaffeine desktop wallpaper =="

WALLPAPER="/usr/share/backgrounds/dicaffeine-background.png"
sudo install -d -m 0755 /usr/share/backgrounds
sudo install -m 0644 "$SRC/background.png" "$WALLPAPER"

echo "== Setting Xfce desktop wallpaper where possible =="

if command -v xfconf-query >/dev/null 2>&1; then
  # Set any existing Xfce wallpaper paths.
  mapfile -t WALL_PATHS < <(
    sudo -u "$TARGET_USER" DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" \
      xfconf-query -c xfce4-desktop -lv 2>/dev/null |
      awk '/last-image/ {print $1}' |
      sort -u
  )

  if [ "${#WALL_PATHS[@]}" -gt 0 ]; then
    for prop in "${WALL_PATHS[@]}"; do
      sudo -u "$TARGET_USER" DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" \
        xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null || true
    done
  else
    echo "No existing Xfce wallpaper properties found. Wallpaper file installed, but desktop may need setting once manually."
  fi
else
  echo "xfconf-query not found; wallpaper file installed but not applied."
fi

echo "== Optionally setting LightDM greeter background =="

if [ -d /etc/lightdm ]; then
  sudo mkdir -p /etc/lightdm

  if [ -f /etc/lightdm/lightdm-gtk-greeter.conf ]; then
    sudo cp /etc/lightdm/lightdm-gtk-greeter.conf \
      "/etc/lightdm/lightdm-gtk-greeter.conf.bak.$(date +%Y%m%d-%H%M%S)"
  fi

  sudo python3 - <<PY
from pathlib import Path

p = Path("/etc/lightdm/lightdm-gtk-greeter.conf")
wallpaper = "$WALLPAPER"

if p.exists():
    lines = p.read_text().splitlines()
else:
    lines = []

out = []
in_greeter = False
seen_greeter = False
set_background = False

for line in lines:
    stripped = line.strip()

    if stripped.startswith("[") and stripped.endswith("]"):
        if in_greeter and not set_background:
            out.append(f"background={wallpaper}")
            set_background = True
        in_greeter = stripped == "[greeter]"
        if in_greeter:
            seen_greeter = True
        out.append(line)
        continue

    if in_greeter and stripped.startswith("background="):
        out.append(f"background={wallpaper}")
        set_background = True
    else:
        out.append(line)

if not seen_greeter:
    if out and out[-1].strip():
        out.append("")
    out.append("[greeter]")
    out.append(f"background={wallpaper}")
elif in_greeter and not set_background:
    out.append(f"background={wallpaper}")

p.write_text("\\n".join(out) + "\\n")
PY
fi

echo
echo "Dicaffeine boot theme and wallpaper installed."
echo
echo "Reboot to test the Plymouth boot splash:"
echo "  sudo reboot"
echo
echo "Installed files:"
echo "  $DEST"
echo "  $WALLPAPER"
