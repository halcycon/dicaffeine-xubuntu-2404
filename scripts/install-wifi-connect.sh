#!/usr/bin/env bash
set -euo pipefail

WFC_REPO="${WFC_REPO:-balena-os/wifi-connect}"
INSTALL_BIN="/usr/local/bin/wifi-connect"
INSTALL_UI_DIR="/usr/local/share/wifi-connect/ui"

echo "== Installing WiFi Connect dependencies =="

sudo apt update
sudo apt install --no-install-recommends -y \
  curl \
  ca-certificates \
  jq \
  tar \
  network-manager \
  dnsmasq-base \
  iw \
  iproute2

echo "== Enabling NetworkManager =="

sudo systemctl enable --now NetworkManager

ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    ASSET_REGEX='linux.*(amd64|x86_64).*\.tar\.gz'
    ;;
  aarch64)
    ASSET_REGEX='linux.*(aarch64|arm64).*\.tar\.gz'
    ;;
  armv7l|armv6l)
    ASSET_REGEX='linux.*(armv7|armhf|rpi).*\.tar\.gz'
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

echo "Detected architecture: $ARCH"
echo "Looking for release asset matching: $ASSET_REGEX"

TMPDIR="$(mktemp -d /tmp/wifi-connect.XXXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

API_URL="https://api.github.com/repos/${WFC_REPO}/releases/latest"

echo "== Fetching latest WiFi Connect release metadata =="

curl -fsSL "$API_URL" -o "$TMPDIR/release.json"

TAG="$(
  jq -r '.tag_name // empty' "$TMPDIR/release.json"
)"

ASSET_URL="$(
  jq -r '.assets[].browser_download_url' "$TMPDIR/release.json" |
    grep -Ei "$ASSET_REGEX" |
    head -n 1
)"

if [ -z "${TAG:-}" ]; then
  echo "ERROR: could not determine latest WiFi Connect release tag." >&2
  cat "$TMPDIR/release.json" >&2
  exit 1
fi

if [ -z "${ASSET_URL:-}" ]; then
  echo "ERROR: could not find a WiFi Connect release asset for architecture: $ARCH" >&2
  echo
  echo "Available assets:" >&2
  jq -r '.assets[].name' "$TMPDIR/release.json" >&2
  exit 1
fi

echo "Latest release: $TAG"
echo "Downloading: $ASSET_URL"

curl -fL --retry 5 "$ASSET_URL" -o "$TMPDIR/wifi-connect.tar.gz"

echo "== Extracting =="

mkdir -p "$TMPDIR/extract"
tar -xzf "$TMPDIR/wifi-connect.tar.gz" -C "$TMPDIR/extract"

echo "Extracted files:"
find "$TMPDIR/extract" -maxdepth 3 -type f -o -type d | sort

WFC_BIN="$(
  find "$TMPDIR/extract" -type f -name wifi-connect -perm /111 | head -n 1
)"

UI_DIR="$(
  find "$TMPDIR/extract" -type d -name ui | head -n 1
)"

if [ -z "${WFC_BIN:-}" ]; then
  echo "ERROR: extracted archive did not contain executable wifi-connect binary." >&2
  exit 1
fi

if [ -z "${UI_DIR:-}" ]; then
  echo "ERROR: extracted archive did not contain ui directory." >&2
  exit 1
fi

echo "== Installing WiFi Connect =="

sudo install -m 0755 "$WFC_BIN" "$INSTALL_BIN"

sudo rm -rf "$INSTALL_UI_DIR"
sudo install -d -m 0755 "$INSTALL_UI_DIR"
sudo cp -a "$UI_DIR"/. "$INSTALL_UI_DIR"/

echo "== Installed version =="

"$INSTALL_BIN" --version || true

echo
echo "WiFi Connect installed:"
echo "  Binary: $INSTALL_BIN"
echo "  UI:     $INSTALL_UI_DIR"
echo
echo "Try:"
echo "  wifi-connect --help"
