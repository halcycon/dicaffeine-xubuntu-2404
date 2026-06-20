#!/usr/bin/env bash
set -euo pipefail

# Install shared /usr/local/bin helpers and default config stubs.
# Safe to re-run on an existing Wyse box (update mode).

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_USER="${SUDO_USER:-${TARGET_USER:-$USER}}"
UPDATE_MODE="${UPDATE_MODE:-0}"

if [ "$TARGET_USER" = "root" ] && [ -z "${SUDO_USER:-}" ]; then
  echo "Run through sudo from the normal desktop user, or set TARGET_USER=." >&2
  exit 1
fi

install_bin() {
  local name="$1"
  local src="${KIT_ROOT}/bin/${name}"
  if [ ! -f "$src" ]; then
    echo "ERROR: missing ${src}" >&2
    exit 1
  fi
  sudo install -m 0755 "$src" "/usr/local/bin/${name}"
}

install_config_if_missing() {
  local name="$1"
  local src="${KIT_ROOT}/config/${name}"
  local dest="/etc/default/${name%.default}"

  if [ ! -f "$src" ]; then
    echo "ERROR: missing ${src}" >&2
    exit 1
  fi

  if [ -f "$dest" ]; then
    echo "Keeping existing ${dest}"
  else
    echo "Installing ${dest}"
    sudo install -m 0644 "$src" "$dest"
    if [ "$name" = "wyse-wifi-setup.default" ]; then
      sudo chown root:"$TARGET_USER" "$dest" 2>/dev/null || true
      sudo chmod 640 "$dest" 2>/dev/null || true
    fi
  fi
}

echo "== Installing shared helpers =="

for helper in \
  wyse-ndi-status \
  wyse-ndi-update-qr \
  wyse-vban-status \
  vban-box-audio-info \
  vban-box-stop-pipewire \
  vban-box-start-pipewire
do
  install_bin "$helper"
done

echo "== Installing default config stubs (only if missing) =="

install_config_if_missing wyse-wifi-setup.default
install_config_if_missing wyse-vban.default

if [ "$UPDATE_MODE" = "1" ]; then
  echo "Update mode: left existing /etc/default/* files unchanged."
fi

echo "Shared helpers installed."
