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
    if [ "$name" = "wyse-vban.default" ]; then
      sudo chown root:"$TARGET_USER" "$dest" 2>/dev/null || true
      sudo chmod 664 "$dest" 2>/dev/null || true
    fi
  else
    echo "Installing ${dest}"
    sudo install -m 0644 "$src" "$dest"
    if [ "$name" = "wyse-wifi-setup.default" ]; then
      sudo chown root:"$TARGET_USER" "$dest" 2>/dev/null || true
      sudo chmod 640 "$dest" 2>/dev/null || true
    fi
    if [ "$name" = "wyse-vban.default" ]; then
      sudo chown root:"$TARGET_USER" "$dest" 2>/dev/null || true
      sudo chmod 664 "$dest" 2>/dev/null || true
    fi
  fi
}

migrate_wyse_vban_config() {
  local dest="/etc/default/wyse-vban"
  local target_user="${TARGET_USER:-ndi}"
  if [ ! -f "$dest" ]; then
    return 0
  fi
  if grep -qE '^VBAN_PULSE_LABEL=VBAN PreService$' "$dest" 2>/dev/null; then
    echo "Migrating VBAN_PULSE_LABEL to \"VBAN AudioBox\" in ${dest}"
    sudo sed -i 's/^VBAN_PULSE_LABEL=VBAN PreService$/VBAN_PULSE_LABEL="VBAN AudioBox"/' "$dest"
  elif grep -qE '^VBAN_PULSE_LABEL="VBAN PreService"$' "$dest" 2>/dev/null; then
    echo "Migrating VBAN_PULSE_LABEL to \"VBAN AudioBox\" in ${dest}"
    sudo sed -i 's/^VBAN_PULSE_LABEL="VBAN PreService"$/VBAN_PULSE_LABEL="VBAN AudioBox"/' "$dest"
  elif grep -qE '^VBAN_PULSE_LABEL=VBAN AudioBox$' "$dest" 2>/dev/null; then
    echo "Fixing unquoted VBAN_PULSE_LABEL in ${dest}"
    sudo sed -i 's/^VBAN_PULSE_LABEL=VBAN AudioBox$/VBAN_PULSE_LABEL="VBAN AudioBox"/' "$dest"
  fi
  sudo chown root:"$target_user" "$dest" 2>/dev/null || true
  sudo chmod 664 "$dest" 2>/dev/null || true
}

echo "== Installing shared helpers =="

for helper in \
  wyse-ndi-status \
  wyse-ndi-update-qr \
  wyse-vban-status \
  wyse-vban-scan \
  wyse-vban-parse-args \
  wyse-vban-audio-devices \
  wyse-vban-audio-levels \
  wyse-vban-save-config \
  vban-box-audio-info \
  vban-box-stop-pipewire \
  vban-box-start-pipewire
do
  install_bin "$helper"
done

echo "== Installing default config stubs (only if missing) =="

install_config_if_missing wyse-wifi-setup.default
install_config_if_missing wyse-vban.default
migrate_wyse_vban_config

if [ "$UPDATE_MODE" = "1" ]; then
  echo "Update mode: left existing /etc/default/* files unchanged."
fi

echo "Shared helpers installed."
