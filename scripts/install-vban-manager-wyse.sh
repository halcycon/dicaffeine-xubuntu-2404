#!/usr/bin/env bash
set -euo pipefail

# Install or update vban + VBAN-manager for the Wyse NDI/VBAN appliance.
#
# Fresh install:
#   sudo APP_USER=ndi bash scripts/install-vban-manager-wyse.sh
#
# Update existing box (refresh patches/units/helpers, skip rebuild unless forced):
#   sudo UPDATE_MODE=1 APP_USER=ndi bash scripts/install-vban-manager-wyse.sh

APP_USER="${APP_USER:-ndi}"
UPDATE_MODE="${UPDATE_MODE:-0}"
FORCE_VBAN_BUILD="${FORCE_VBAN_BUILD:-0}"
WEB_PORT="${WEB_PORT:-}"
INSTALL_BASE="${INSTALL_BASE:-/opt}"
VBAN_REPO="${VBAN_REPO:-https://github.com/quiniouben/vban.git}"
MANAGER_REPO="${MANAGER_REPO:-https://github.com/VBAN-manager/VBAN-manager.git}"
VBAN_DIR="${VBAN_DIR:-${INSTALL_BASE}/vban}"
MANAGER_DIR="${MANAGER_DIR:-${INSTALL_BASE}/vban-manager}"
BIND_ADDR="${BIND_ADDR:-}"

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="${KIT_ROOT}/patches/vban-manager"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root, e.g. sudo APP_USER=${APP_USER} bash $0" >&2
  exit 1
fi

if ! id "${APP_USER}" >/dev/null 2>&1; then
  echo "User ${APP_USER} does not exist." >&2
  exit 1
fi

if [ -f /etc/default/wyse-vban ]; then
  # shellcheck disable=SC1091
  . /etc/default/wyse-vban
fi

MANAGER_DIR="${VBAN_MANAGER_DIR:-${MANAGER_DIR}}"
WEB_PORT="${WEB_PORT:-${VBAN_MANAGER_PORT:-8088}}"
BIND_ADDR="${BIND_ADDR:-${VBAN_MANAGER_BIND:-0.0.0.0}}"

APP_UID="$(id -u "${APP_USER}")"
APP_HOME="$(getent passwd "${APP_USER}" | cut -d: -f6)"
USER_SYSTEMD_DIR="${APP_HOME}/.config/systemd/user"

log() { printf '\n== %s ==\n' "$*"; }

run_as_user() {
  sudo -u "${APP_USER}" XDG_RUNTIME_DIR="/run/user/${APP_UID}" "$@"
}

need_vban_build=true
if [[ "$UPDATE_MODE" = "1" && "$FORCE_VBAN_BUILD" != "1" ]] && command -v vban_receptor >/dev/null 2>&1; then
  need_vban_build=false
fi

if [[ "$need_vban_build" = true ]]; then
  log "Installing build packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates git curl \
    build-essential autoconf automake libtool pkg-config \
    libasound2-dev libpulse-dev alsa-utils \
    php-cli
else
  log "Update mode: skipping vban rebuild (set FORCE_VBAN_BUILD=1 to rebuild)"
  DEBIAN_FRONTEND=noninteractive apt-get install -y php-cli 2>/dev/null || \
    apt-get install -y php-cli || true
fi

if [[ "$need_vban_build" = true ]]; then
  log "Cloning/updating vban"
  if [[ -d "${VBAN_DIR}/.git" ]]; then
    git -C "${VBAN_DIR}" fetch --all --prune
    git -C "${VBAN_DIR}" pull --ff-only || true
  else
    git clone "${VBAN_REPO}" "${VBAN_DIR}"
  fi
  chown -R "${APP_USER}:${APP_USER}" "${VBAN_DIR}"

  log "Building/installing vban"
  cd "${VBAN_DIR}"
  if [[ -x ./autogen.sh ]]; then
    run_as_user ./autogen.sh
  fi
  run_as_user ./configure --disable-jack
  run_as_user make -j"$(nproc)"
  make install
  ldconfig || true

  if ! command -v vban_receptor >/dev/null 2>&1; then
    echo "vban_receptor was not found after install." >&2
    exit 1
  fi
fi

log "Cloning/updating VBAN-manager"
if [[ -d "${MANAGER_DIR}/.git" ]]; then
  git -C "${MANAGER_DIR}" fetch --all --prune || true
  git -C "${MANAGER_DIR}" pull --ff-only || true
else
  git clone "${MANAGER_REPO}" "${MANAGER_DIR}"
fi
chown -R "${APP_USER}:${APP_USER}" "${MANAGER_DIR}"

log "Applying maintained VBAN-manager patches from ${PATCH_DIR}"
if [[ ! -f "${PATCH_DIR}/action.php" || ! -f "${PATCH_DIR}/vban.sh" ]]; then
  echo "ERROR: missing patch files in ${PATCH_DIR}" >&2
  exit 1
fi

install_patch_file() {
  local rel="$1"
  local mode="${2:-0644}"
  local src="${PATCH_DIR}/${rel}"
  local dest="${MANAGER_DIR}/${rel}"
  if [[ ! -f "${src}" ]]; then
    return 0
  fi
  install -d -o "${APP_USER}" -g "${APP_USER}" "$(dirname "${dest}")"
  install -o "${APP_USER}" -g "${APP_USER}" -m "${mode}" "${src}" "${dest}"
}

for patch_file in \
  config.php \
  action.php \
  modify_args.php \
  index.php \
  top.php \
  server.php \
  audiobox.php \
  scan.php \
  connect.php \
  disconnect.php \
  status-api.php \
  settings.php \
  save-settings.php \
  audio-devices.php \
  audio-levels-api.php \
  volume-api.php \
  bottom.php \
  wyse-common.php
do
  install_patch_file "${patch_file}"
done

install_patch_file "css/wyse-audiobox.css"
install -d -o "${APP_USER}" -g "${APP_USER}" "${MANAGER_DIR}/js"
install -o "${APP_USER}" -g "${APP_USER}" -m 0644 "${PATCH_DIR}/js/wyse-app.js" "${MANAGER_DIR}/js/wyse-app.js"
install -o "${APP_USER}" -g "${APP_USER}" -m 0755 "${PATCH_DIR}/vban.sh" "${MANAGER_DIR}/script/vban.sh"

nested_args="${MANAGER_DIR}/script/script"
if [[ -d "${nested_args}" ]]; then
  shopt -s nullglob
  for misplaced in "${nested_args}"/args-*.txt; do
    log "Moving misplaced $(basename "${misplaced}") into script/"
    mv -f "${misplaced}" "${MANAGER_DIR}/script/"
  done
  shopt -u nullglob
  rmdir "${nested_args}" 2>/dev/null || true
fi

log "Installing shared helpers and /etc/default/wyse-vban stub"
UPDATE_MODE="$UPDATE_MODE" TARGET_USER="$APP_USER" bash "${KIT_ROOT}/scripts/install-common-helpers.sh"

log "Creating user-level systemd services"
install -d -o "${APP_USER}" -g "${APP_USER}" "${USER_SYSTEMD_DIR}"

sed \
  -e "s|@MANAGER_DIR@|${MANAGER_DIR}|g" \
  -e "s|@APP_UID@|${APP_UID}|g" \
  "${PATCH_DIR}/vban@.service.in" > "${USER_SYSTEMD_DIR}/vban@.service"

sed \
  -e "s|@MANAGER_DIR@|${MANAGER_DIR}|g" \
  -e "s|@BIND_ADDR@|${BIND_ADDR}|g" \
  -e "s|@WEB_PORT@|${WEB_PORT}|g" \
  -e "s|@APP_UID@|${APP_UID}|g" \
  "${PATCH_DIR}/vban-manager-web.service.in" > "${USER_SYSTEMD_DIR}/vban-manager-web.service"

chown "${APP_USER}:${APP_USER}" "${USER_SYSTEMD_DIR}/vban@.service" "${USER_SYSTEMD_DIR}/vban-manager-web.service"

log "Enabling lingering and starting user services"
loginctl enable-linger "${APP_USER}"
systemctl start "user@${APP_UID}.service" || true

if [[ ! -d "/run/user/${APP_UID}" ]]; then
  echo "Warning: /run/user/${APP_UID} does not exist yet. Reboot or log in as ${APP_USER}, then:" >&2
  echo "  systemctl --user daemon-reload" >&2
  echo "  systemctl --user enable --now vban-manager-web.service" >&2
else
  run_as_user systemctl --user daemon-reload
  run_as_user systemctl --user enable vban-manager-web.service
  if [[ "$UPDATE_MODE" = "1" ]]; then
    run_as_user systemctl --user try-restart vban-manager-web.service || \
      run_as_user systemctl --user start vban-manager-web.service || true
    for args_file in "${MANAGER_DIR}/script/args-"*.txt; do
      [[ -f "${args_file}" ]] || continue
      slot_id="${args_file##*/args-}"
      slot_id="${slot_id%.txt}"
      if run_as_user systemctl --user is-active "vban@${slot_id}.service" >/dev/null 2>&1; then
        run_as_user systemctl --user restart "vban@${slot_id}.service" || true
      fi
    done
  else
    run_as_user systemctl --user enable --now vban-manager-web.service
  fi
fi

if command -v wyse-vban-update-qr >/dev/null 2>&1; then
  log "Refreshing VBAN overlay QR"
  wyse-vban-update-qr || true
fi

log "Done"
primary_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
if [ -z "${primary_ip:-}" ]; then
  primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [ -n "${primary_ip:-}" ]; then
  echo "VBAN AudioBox URL: http://${primary_ip}:${WEB_PORT}/audiobox.php"
else
  echo "VBAN AudioBox URL: http://<wyse-ip>:${WEB_PORT}/audiobox.php"
fi

echo
echo "Config: /etc/default/wyse-vban"
echo "Overlay: wyse-vban-status"
echo
echo "Notes:"
echo "  - VBAN and Dicaffeine/NDI may run together when using PipeWire/PulseAudio."
echo "  - No sudoers rule is installed; web UI and VBAN processes run as ${APP_USER}."
echo "  - Keep VBAN-manager on a trusted LAN only; upstream has no built-in auth."
echo "  - Set VBAN_MANAGER_BIND in /etc/default/wyse-vban to limit listen address."
