#!/usr/bin/env bash
set -euo pipefail

echo "== Checking sudo access =="
sudo -v

WFC_REPO="${WFC_REPO:-balena-io/wifi-connect}"
WFC_VERSION="${WFC_VERSION:-latest}"
WFC_ASSET_URL="${WFC_ASSET_URL:-}"

INSTALL_BIN="/usr/local/bin/wifi-connect"
INSTALL_BASE="/usr/local/share/wifi-connect"
INSTALL_UI_DIR="${INSTALL_BASE}/ui"

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
    ASSET_REGEX='^wifi-connect-(x86_64|amd64|x64).*-linux-.*\.tar\.gz$'
    ;;
  aarch64)
    ASSET_REGEX='^wifi-connect-(aarch64|arm64).*-linux-.*\.tar\.gz$'
    ;;
  armv7l|armv6l)
    ASSET_REGEX='^wifi-connect-(armv7|armhf|arm).*-linux-.*\.tar\.gz$'
    ;;
  i386|i686)
    ASSET_REGEX='^wifi-connect-(i686|i386|x86).*-linux-.*\.tar\.gz$'
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

UI_ASSET_URL=""

if [ -n "$WFC_ASSET_URL" ]; then
  echo "Using explicit WFC_ASSET_URL:"
  echo "  $WFC_ASSET_URL"
  ASSET_URL="$WFC_ASSET_URL"
  TAG="manual"
else
  if [ "$WFC_VERSION" = "latest" ]; then
    API_URL="https://api.github.com/repos/${WFC_REPO}/releases/latest"
  else
    API_URL="https://api.github.com/repos/${WFC_REPO}/releases/tags/${WFC_VERSION}"
  fi

  echo "== Fetching WiFi Connect release metadata =="
  echo "GitHub API: $API_URL"

  curl -4 -fL --retry 5 --connect-timeout 15 --max-time 60 \
    "$API_URL" \
    -o "$TMPDIR/release.json"

  TAG="$(
    jq -r '.tag_name // empty' "$TMPDIR/release.json"
  )"

  if [ -z "${TAG:-}" ]; then
    echo "ERROR: could not determine WiFi Connect release tag." >&2
    echo "GitHub API response was:" >&2
    cat "$TMPDIR/release.json" >&2
    exit 1
  fi

  echo "Release: $TAG"
  echo
  echo "Available assets:"
  jq -r '.assets[].name' "$TMPDIR/release.json" | sed 's/^/  - /'

  ASSET_URL="$(
    jq -r --arg re "$ASSET_REGEX" \
      '.assets[] | select(.name | test($re; "i")) | .browser_download_url' \
      "$TMPDIR/release.json" |
      head -n 1 || true
  )"

  UI_ASSET_URL="$(
    jq -r \
      '.assets[] | select(.name == "wifi-connect-ui.tar.gz") | .browser_download_url' \
      "$TMPDIR/release.json" |
      head -n 1 || true
  )"

  if [ -z "${ASSET_URL:-}" ]; then
    echo
    echo "ERROR: could not find a WiFi Connect binary release asset for architecture: $ARCH" >&2
    echo
    echo "Tried regex:" >&2
    echo "  $ASSET_REGEX" >&2
    echo
    echo "Available assets were:" >&2
    jq -r '.assets[].name' "$TMPDIR/release.json" | sed 's/^/  - /' >&2
    echo
    echo "You can override this by passing an explicit binary release asset URL:" >&2
    echo "  WFC_ASSET_URL='https://github.com/.../asset.tar.gz' ./scripts/install-wifi-connect.sh" >&2
    echo
    echo "Or pin a release tag:" >&2
    echo "  WFC_VERSION='vX.Y.Z' ./scripts/install-wifi-connect.sh" >&2
    exit 1
  fi
fi

echo
echo "Downloading WiFi Connect binary asset:"
echo "  $ASSET_URL"

curl -4 -fL --retry 5 --connect-timeout 15 --max-time 120 \
  "$ASSET_URL" \
  -o "$TMPDIR/wifi-connect.tar.gz"

echo "== Extracting binary asset =="

mkdir -p "$TMPDIR/extract-bin"
tar -xzf "$TMPDIR/wifi-connect.tar.gz" -C "$TMPDIR/extract-bin"

echo "Extracted binary asset files:"
find "$TMPDIR/extract-bin" -maxdepth 3 \( -type f -o -type d \) | sort

WFC_BIN="$(
  find "$TMPDIR/extract-bin" -type f -name wifi-connect -perm /111 | head -n 1 || true
)"

if [ -z "${WFC_BIN:-}" ]; then
  WFC_BIN="$(
    find "$TMPDIR/extract-bin" -type f -name wifi-connect | head -n 1 || true
  )"
fi

if [ -z "${WFC_BIN:-}" ]; then
  echo "ERROR: extracted archive did not contain a wifi-connect binary." >&2
  exit 1
fi

echo "== Installing WiFi Connect binary =="

sudo install -d -m 0755 /usr/local/bin
sudo install -m 0755 "$WFC_BIN" "$INSTALL_BIN"

echo "== Installing WiFi Connect UI =="

sudo install -d -m 0755 "$INSTALL_BASE"
sudo rm -rf "$INSTALL_UI_DIR"
sudo install -d -m 0755 "$INSTALL_UI_DIR"

if [ -n "${UI_ASSET_URL:-}" ]; then
  echo "Downloading UI asset:"
  echo "  $UI_ASSET_URL"

  curl -4 -fL --retry 5 --connect-timeout 15 --max-time 120 \
    "$UI_ASSET_URL" \
    -o "$TMPDIR/wifi-connect-ui.tar.gz"

  mkdir -p "$TMPDIR/extract-ui"
  tar -xzf "$TMPDIR/wifi-connect-ui.tar.gz" -C "$TMPDIR/extract-ui"

  echo "Extracted UI asset files:"
  find "$TMPDIR/extract-ui" -maxdepth 3 \( -type f -o -type d \) | sort

  # The UI archive may either contain files directly, or a ui/ directory.
  UI_DIR="$(
    find "$TMPDIR/extract-ui" -type d -name ui | head -n 1 || true
  )"

  if [ -n "${UI_DIR:-}" ] && [ -d "$UI_DIR" ]; then
    sudo cp -a "$UI_DIR"/. "$INSTALL_UI_DIR"/
  else
    sudo cp -a "$TMPDIR/extract-ui"/. "$INSTALL_UI_DIR"/
  fi
else
  echo "No separate wifi-connect-ui.tar.gz asset found."
  echo "This may be OK if this WiFi Connect build embeds its UI assets."
fi

echo "== Installed version/help =="

if "$INSTALL_BIN" --version >/tmp/wifi-connect-version.out 2>&1; then
  cat /tmp/wifi-connect-version.out
else
  echo "wifi-connect --version did not return successfully; continuing."
fi

echo
echo "Installed binary:"
echo "  $INSTALL_BIN"

if [ -d "$INSTALL_UI_DIR" ]; then
  echo "Installed UI directory:"
  echo "  $INSTALL_UI_DIR"
  echo
  echo "UI directory contents:"
  find "$INSTALL_UI_DIR" -maxdepth 2 \( -type f -o -type d \) | sort | sed 's/^/  /'
fi

echo
echo "Checking available options:"
"$INSTALL_BIN" --help | sed -n '1,160p' || true

echo
echo "WiFi Connect installed."
echo
echo "Next useful checks:"
echo "  which wifi-connect"
echo "  wifi-connect --help"
echo
echo "Manual test example:"
echo "  sudo wifi-connect --portal-ssid Dicaffeine-Setup --portal-passphrase dicaffeine --portal-gateway 192.168.42.1 --portal-listening-port 80"
