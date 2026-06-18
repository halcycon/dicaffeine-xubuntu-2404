#!/usr/bin/env bash
set -euo pipefail

LIBNDI_INSTALLER_NAME="Install_NDI_SDK_v6_Linux"
LIBNDI_INSTALLER="${LIBNDI_INSTALLER_NAME}.tar.gz"
LIBNDI_INSTALLER_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Linux/${LIBNDI_INSTALLER}"

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)
        LIB_ARCH="x86_64-linux-gnu"
        ;;
    aarch64)
        LIB_ARCH="aarch64-rpi4-linux-gnueabi"
        ;;
    armv7l)
        LIB_ARCH="arm-rpi4-linux-gnueabihf"
        ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH"
echo "Using NDI SDK library path: $LIB_ARCH"
echo
echo "This script downloads the NDI SDK from NDI's official download URL."
echo "Use of the SDK is subject to NDI's licence terms."
echo

if [ "${1:-}" != "--yes" ]; then
    read -r -p "Continue and download/install NDI SDK v6? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *)
            echo "Aborted."
            exit 1
            ;;
    esac
fi

sudo apt update
sudo apt install --no-install-recommends -y \
    curl \
    ca-certificates \
    tar \
    avahi-daemon \
    libavahi-common3 \
    libavahi-client3

TMPDIR="$(mktemp -d /tmp/ndisdk.XXXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"

echo "Downloading NDI SDK v6..."
curl -L --fail --retry 5 \
    "$LIBNDI_INSTALLER_URL" \
    -o "$LIBNDI_INSTALLER"

echo "Extracting SDK installer archive..."
tar -xzf "$LIBNDI_INSTALLER"

echo "Running NDI SDK extractor..."
yes | PAGER=cat sh "${LIBNDI_INSTALLER_NAME}.sh"

if [ ! -d "NDI SDK for Linux" ]; then
    echo "ERROR: expected SDK directory was not created." >&2
    find "$TMPDIR" -maxdepth 2 -type d | sort >&2
    exit 1
fi

mv "NDI SDK for Linux" ndisdk

SDK_LIB_DIR="$TMPDIR/ndisdk/lib/$LIB_ARCH"

if [ ! -d "$SDK_LIB_DIR" ]; then
    echo "ERROR: library path not found: $SDK_LIB_DIR" >&2
    echo "Available architectures:" >&2
    find "$TMPDIR/ndisdk/lib" -maxdepth 1 -mindepth 1 -type d -printf '  %f\n' >&2
    exit 1
fi

echo "Installing NDI runtime libraries..."

sudo mkdir -p /usr/local/lib/ndi
sudo mkdir -p /usr/local/include

sudo cp -P "$SDK_LIB_DIR"/libndi.so* /usr/local/lib/ndi/

if [ -d "$TMPDIR/ndisdk/include" ]; then
    sudo cp -r "$TMPDIR/ndisdk/include/"* /usr/local/include/
fi

REAL_NDI="$(
    sudo find -L /usr/local/lib/ndi \
        -type f -name 'libndi.so*' 2>/dev/null | sort -V | tail -1
)"

if [ -z "${REAL_NDI:-}" ]; then
    echo "ERROR: libndi.so was not installed." >&2
    exit 1
fi

echo "Using NDI library: $REAL_NDI"

sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so
sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so.5
sudo ln -sfn "$REAL_NDI" /usr/local/lib/libndi.so.6

echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/ndi-local.conf >/dev/null
echo "/usr/local/lib/ndi" | sudo tee /etc/ld.so.conf.d/ndi-sdk.conf >/dev/null

sudo ldconfig

sudo systemctl enable --now avahi-daemon

echo
echo "Installed NDI libraries:"
ls -l /usr/local/lib/ndi/libndi.so* /usr/local/lib/libndi.so* 2>/dev/null || true

echo
echo "ldconfig sees:"
ldconfig -p | grep -i libndi || true

echo
echo "NDI SDK v6 install complete."
