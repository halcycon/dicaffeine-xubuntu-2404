#!/usr/bin/env bash
set -euo pipefail

# Disable XFCE's "Configure new displays when connected" dialog.
# Headless Wyse installs often hot-plug a monitor without keyboard/mouse;
# the minimal display dialog blocks the desktop until dismissed.

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$USER}}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [ "$TARGET_USER" = "root" ] || [ -z "${TARGET_HOME:-}" ]; then
  echo "Set TARGET_USER to the desktop user (e.g. ndi)." >&2
  exit 1
fi

if ! command -v xfconf-query >/dev/null 2>&1; then
  echo "xfconf-query not found; skipping XFCE display hotplug dialog disable."
  exit 0
fi

xfconf_as_user() {
  sudo -u "$TARGET_USER" \
    DISPLAY="${DISPLAY:-:0}" \
    XAUTHORITY="${XAUTHORITY:-$TARGET_HOME/.Xauthority}" \
    xfconf-query "$@"
}

disable_notify_bool() {
  xfconf_as_user -c displays -p /Notify -n -t bool -s false 2>/dev/null \
    || xfconf_as_user -c displays -p /Notify -s false 2>/dev/null \
    || return 1
}

disable_notify_int() {
  # XFCE 4.20+ uses an enum: 0 = do nothing (no dialog).
  xfconf_as_user -c displays -p /Notify -n -t int -s 0 2>/dev/null \
    || xfconf_as_user -c displays -p /Notify -s 0 2>/dev/null \
    || return 1
}

notify_prop="$(xfconf_as_user -c displays -p /Notify 2>/dev/null || true)"
if [ -z "$notify_prop" ]; then
  disable_notify_bool || disable_notify_int || true
elif [[ "$notify_prop" =~ ^[0-9]+$ ]]; then
  disable_notify_int || true
else
  disable_notify_bool || true
fi

echo "XFCE new-display dialog disabled for ${TARGET_USER} (displays/Notify)."
