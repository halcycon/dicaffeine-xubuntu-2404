#!/usr/bin/env bash
set -euo pipefail

# Passwordless sudo for the ndi appliance user (kit install/update only).
# Installed to /etc/sudoers.d/wyse-ndi-kit

TARGET_USER="${TARGET_USER:-${SUDO_USER:-ndi}}"
UPDATE_MODE="${UPDATE_MODE:-0}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo TARGET_USER=${TARGET_USER} bash $0" >&2
  exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "User ${TARGET_USER} does not exist." >&2
  exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/wyse-ndi-kit"

tee "$SUDOERS_FILE" >/dev/null <<EOF
# Wyse NDI/VBAN appliance — allow ${TARGET_USER} to run kit install/update without a password.
# Installed by wyse-ndi-kit. Do not hand-edit; re-run scripts/install-sudoers-wyse-kit.sh
Defaults:${TARGET_USER} !requiretty

${TARGET_USER} ALL=(ALL) NOPASSWD: SETENV: /opt/wyse-ndi-kit/install-wyse-ndi.sh
${TARGET_USER} ALL=(ALL) NOPASSWD: SETENV: /opt/wyse-ndi-kit/scripts/*
${TARGET_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg
${TARGET_USER} ALL=(ALL) NOPASSWD: /usr/bin/install, /usr/bin/systemctl, /usr/bin/loginctl
${TARGET_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee, /usr/bin/sed, /usr/bin/rsync, /usr/bin/python3
${TARGET_USER} ALL=(ALL) NOPASSWD: /bin/chown, /bin/chmod, /bin/mkdir, /bin/cp, /bin/mv, /bin/rm, /bin/ln
${TARGET_USER} ALL=(ALL) NOPASSWD: /usr/sbin/update-grub, /usr/sbin/update-initramfs, /usr/bin/ldconfig
${TARGET_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/wyse-*, /usr/local/bin/vban-box-*
EOF

chmod 0440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

echo "Installed ${SUDOERS_FILE} for user ${TARGET_USER}"
