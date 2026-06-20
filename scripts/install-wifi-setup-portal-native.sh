#!/usr/bin/env bash
set -euo pipefail

UPDATE_MODE="${UPDATE_MODE:-0}"
KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Checking sudo access =="
sudo -v

TARGET_USER="${SUDO_USER:-${TARGET_USER:-ndi}}"
SETUP_SSID="${SETUP_SSID:-Dicaffeine-Setup}"
SETUP_PASSPHRASE="${SETUP_PASSPHRASE:-dicaffeine}"
SETUP_GATEWAY="${SETUP_GATEWAY:-192.168.44.1}"
SETUP_CIDR="${SETUP_CIDR:-192.168.44.1/24}"
SETUP_PORT="${SETUP_PORT:-80}"
QR_DIR="${QR_DIR:-/var/lib/wyse-ndi}"

if [ "$UPDATE_MODE" != "1" ] || ! command -v nmcli >/dev/null 2>&1; then
  echo "== Installing native Wi-Fi setup portal dependencies =="

  sudo apt update
  sudo apt install --no-install-recommends -y \
    network-manager \
    dnsmasq-base \
    iw \
    qrencode \
    python3 \
    iproute2
else
  echo "== Update mode: NetworkManager already installed; refreshing portal scripts =="
fi

UPDATE_MODE="$UPDATE_MODE" TARGET_USER="$TARGET_USER" bash "${KIT_ROOT}/scripts/install-common-helpers.sh"

echo "== Fixing netplan permissions warning, if present =="

if [ -f /etc/netplan/01-network-manager-all.yaml ]; then
  sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
  sudo netplan generate || true
fi

echo "== Writing config =="

if [ -f /etc/default/wyse-wifi-setup ] && [ "$UPDATE_MODE" = "1" ] && [ "${FORCE_WIFI_CONFIG:-0}" != "1" ]; then
  echo "Update mode: keeping existing /etc/default/wyse-wifi-setup"
else
  sudo tee /etc/default/wyse-wifi-setup >/dev/null <<EOFCONF
TARGET_USER=$(printf '%q' "$TARGET_USER")
SETUP_SSID=$(printf '%q' "$SETUP_SSID")
SETUP_PASSPHRASE=$(printf '%q' "$SETUP_PASSPHRASE")
SETUP_GATEWAY=$(printf '%q' "$SETUP_GATEWAY")
SETUP_CIDR=$(printf '%q' "$SETUP_CIDR")
SETUP_PORT=$(printf '%q' "$SETUP_PORT")
QR_DIR=$(printf '%q' "$QR_DIR")
EOFCONF

  # This file is read by root services and by the desktop overlay helper running as TARGET_USER.
  # It contains only setup-mode defaults, not saved venue Wi-Fi credentials.
  sudo chown root:"$TARGET_USER" /etc/default/wyse-wifi-setup
  sudo chmod 640 /etc/default/wyse-wifi-setup
fi



echo "== Preparing QR/status directory =="

sudo install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$QR_DIR"

# Avoid Ubuntu protected_regular issues in sticky /tmp when root/user both update QR files.
sudo rm -f /tmp/dicaffeine-webui-qr.png /tmp/dicaffeine-webui-url.txt
sudo rm -f /tmp/vban-audiobox-qr.png /tmp/vban-audiobox-url.txt
sudo ln -sf "$QR_DIR/dicaffeine-webui-qr.png" /tmp/dicaffeine-webui-qr.png
sudo ln -sf "$QR_DIR/dicaffeine-webui-url.txt" /tmp/dicaffeine-webui-url.txt
sudo ln -sf "$QR_DIR/vban-audiobox-qr.png" /tmp/vban-audiobox-qr.png
sudo ln -sf "$QR_DIR/vban-audiobox-url.txt" /tmp/vban-audiobox-url.txt

CONKY_CONF="/home/$TARGET_USER/.config/conky/wyse-ndi.conf"
if [ -f "$CONKY_CONF" ]; then
  sudo sed -i \
    "s#/tmp/dicaffeine-webui-qr.png#$QR_DIR/dicaffeine-webui-qr.png#g" \
    "$CONKY_CONF"
  sudo chown "$TARGET_USER:$TARGET_USER" "$CONKY_CONF"
fi

echo "== Adding captive DNS redirect for NetworkManager shared hotspots =="

sudo install -d -m 0755 /etc/NetworkManager/dnsmasq-shared.d

sudo tee /etc/NetworkManager/dnsmasq-shared.d/wyse-captive.conf >/dev/null <<EOFNM
# Used by NetworkManager's shared-connection dnsmasq instance.
# During setup mode, force clients to resolve names to the local setup portal.
address=/#/${SETUP_GATEWAY}
EOFNM

echo "== Installing Dicaffeine user-service helper =="

sudo tee /usr/local/bin/wyse-dicaffeine-userctl >/dev/null <<'EOFUSERCTL'
#!/usr/bin/env bash
set -euo pipefail

. /etc/default/wyse-wifi-setup

TARGET_UID="$(id -u "$TARGET_USER")"

export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus"

exec sudo -u "$TARGET_USER" env \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  systemctl --user "$@"
EOFUSERCTL

sudo chmod +x /usr/local/bin/wyse-dicaffeine-userctl

echo "== Installing AP start helper =="

sudo tee /usr/local/bin/wyse-wifi-setup-ap-start >/dev/null <<'EOFAPSTART'
#!/usr/bin/env bash
set -euo pipefail

. /etc/default/wyse-wifi-setup

STATE_DIR="/run/wyse-wifi-setup"
STATE_FILE="${STATE_DIR}/state"
NETWORKS_FILE="${STATE_DIR}/networks.txt"

mkdir -p "$STATE_DIR"

wifi_iface="${WYSE_WIFI_SETUP_IFACE:-}"

if [ -z "$wifi_iface" ]; then
  wifi_iface="$(
    nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
      awk -F: '$2=="wifi" && $1 != "" {print $1; exit}'
  )"
fi

if [ -z "$wifi_iface" ]; then
  echo "No Wi-Fi interface found." >&2
  exit 1
fi

if ! iw list 2>/dev/null | grep -q '^[[:space:]]*\* AP$'; then
  echo "Wi-Fi adapter does not support AP mode." >&2
  exit 1
fi

nmcli radio wifi on || true

# Capture scan results before AP mode takes over the adapter.
nmcli -t --escape yes -f SSID,SIGNAL,SECURITY dev wifi list ifname "$wifi_iface" --rescan yes \
  > "$NETWORKS_FILE" 2>/dev/null || true

nmcli connection down "$SETUP_SSID" 2>/dev/null || true
nmcli connection delete "$SETUP_SSID" 2>/dev/null || true

nmcli connection add \
  type wifi \
  ifname "$wifi_iface" \
  con-name "$SETUP_SSID" \
  autoconnect no \
  ssid "$SETUP_SSID"

# Conservative settings that work well on phones:
# 2.4 GHz, channel 6, WPA2/RSN, CCMP only, PMF optional.
nmcli connection modify "$SETUP_SSID" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  802-11-wireless.channel 6 \
  802-11-wireless.hidden no \
  ipv4.method shared \
  ipv4.addresses "$SETUP_CIDR" \
  ipv6.method disabled \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.proto rsn \
  wifi-sec.pairwise ccmp \
  wifi-sec.group ccmp \
  wifi-sec.pmf 1 \
  wifi-sec.psk "$SETUP_PASSPHRASE"

{
  printf 'WYSE_WIFI_SETUP_ACTIVE=1\n'
  printf 'WYSE_WIFI_SETUP_CONNECTING=0\n'
  printf 'WYSE_WIFI_SETUP_SSID=%q\n' "$SETUP_SSID"
  printf 'WYSE_WIFI_SETUP_PASSPHRASE=%q\n' "$SETUP_PASSPHRASE"
  printf 'WYSE_WIFI_SETUP_GATEWAY=%q\n' "$SETUP_GATEWAY"
  printf 'WYSE_WIFI_SETUP_IFACE=%q\n' "$wifi_iface"
  printf 'WYSE_WIFI_SETUP_STARTED=%q\n' "$(date +%s)"
} > "$STATE_FILE"

nmcli connection up "$SETUP_SSID"

if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
  wyse-ndi-update-qr || true
fi
EOFAPSTART

sudo chmod +x /usr/local/bin/wyse-wifi-setup-ap-start

echo "== Installing AP stop helper =="

sudo tee /usr/local/bin/wyse-wifi-setup-ap-stop >/dev/null <<'EOFAPSTOP'
#!/usr/bin/env bash
set -euo pipefail

. /etc/default/wyse-wifi-setup

nmcli connection down "$SETUP_SSID" 2>/dev/null || true
nmcli connection delete "$SETUP_SSID" 2>/dev/null || true

if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
  wyse-ndi-update-qr || true
fi
EOFAPSTOP

sudo chmod +x /usr/local/bin/wyse-wifi-setup-ap-stop

echo "== Installing Wi-Fi apply helper =="

sudo tee /usr/local/bin/wyse-wifi-setup-apply >/dev/null <<'EOFAPPLY'
#!/usr/bin/env bash
set -euo pipefail

. /etc/default/wyse-wifi-setup

STATE_DIR="/run/wyse-wifi-setup"
STATE_FILE="${STATE_DIR}/state"
CREDENTIALS_FILE="${STATE_DIR}/credentials.json"

sleep 2

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "No credentials file found." >&2
  exit 1
fi

mapfile -t creds < <(python3 - "$CREDENTIALS_FILE" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("ssid", ""))
print(data.get("password", ""))
print(data.get("iface", ""))
PY
)

ssid="${creds[0]:-}"
password="${creds[1]:-}"
iface="${creds[2]:-}"

rm -f "$CREDENTIALS_FILE"

if [ -z "$ssid" ]; then
  echo "SSID was empty." >&2
  exit 1
fi

if [ -z "$iface" ]; then
  iface="$(
    nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
      awk -F: '$2=="wifi" && $1 != "" {print $1; exit}'
  )"
fi

{
  printf 'WYSE_WIFI_SETUP_ACTIVE=1\n'
  printf 'WYSE_WIFI_SETUP_CONNECTING=1\n'
  printf 'WYSE_WIFI_SETUP_SSID=%q\n' "$SETUP_SSID"
  printf 'WYSE_WIFI_SETUP_PASSPHRASE=%q\n' "$SETUP_PASSPHRASE"
  printf 'WYSE_WIFI_SETUP_GATEWAY=%q\n' "$SETUP_GATEWAY"
  printf 'WYSE_WIFI_SETUP_IFACE=%q\n' "$iface"
  printf 'WYSE_WIFI_SETUP_TARGET_SSID=%q\n' "$ssid"
  printf 'WYSE_WIFI_SETUP_STARTED=%q\n' "$(date +%s)"
} > "$STATE_FILE"

if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
  wyse-ndi-update-qr || true
fi

# Stop the portal service, which also brings down the setup AP.
systemctl stop wyse-wifi-setup-portal.service || true

nmcli radio wifi on || true
sleep 2
nmcli dev wifi rescan ifname "$iface" 2>/dev/null || true
sleep 2

set +e
if [ -n "$password" ]; then
  nmcli dev wifi connect "$ssid" password "$password" ifname "$iface"
else
  nmcli dev wifi connect "$ssid" ifname "$iface"
fi
connect_rc=$?
set -e

if [ "$connect_rc" -eq 0 ]; then
  for _ in $(seq 1 25); do
    if ip -4 addr show dev "$iface" scope global 2>/dev/null | grep -q 'inet '; then
      rm -f "$STATE_FILE"

      if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
        wyse-ndi-update-qr || true
      fi

      wyse-dicaffeine-userctl start dicaffeine || true
      exit 0
    fi

    sleep 1
  done
fi

{
  printf 'WYSE_WIFI_SETUP_ACTIVE=1\n'
  printf 'WYSE_WIFI_SETUP_CONNECTING=0\n'
  printf 'WYSE_WIFI_SETUP_ERROR=%q\n' "Failed_to_connect_to_${ssid}"
  printf 'WYSE_WIFI_SETUP_SSID=%q\n' "$SETUP_SSID"
  printf 'WYSE_WIFI_SETUP_PASSPHRASE=%q\n' "$SETUP_PASSPHRASE"
  printf 'WYSE_WIFI_SETUP_GATEWAY=%q\n' "$SETUP_GATEWAY"
  printf 'WYSE_WIFI_SETUP_IFACE=%q\n' "$iface"
  printf 'WYSE_WIFI_SETUP_STARTED=%q\n' "$(date +%s)"
} > "$STATE_FILE"

if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
  wyse-ndi-update-qr || true
fi

systemctl start wyse-wifi-setup-portal.service || true
EOFAPPLY

sudo chmod +x /usr/local/bin/wyse-wifi-setup-apply

echo "== Installing Python portal =="

sudo tee /usr/local/bin/wyse-wifi-setup-portal >/dev/null <<'EOFPORTAL'
#!/usr/bin/env python3
import html
import json
import os
import shlex
import subprocess
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_FILE = "/etc/default/wyse-wifi-setup"
STATE_DIR = "/run/wyse-wifi-setup"
STATE_FILE = f"{STATE_DIR}/state"
NETWORKS_FILE = f"{STATE_DIR}/networks.txt"
CREDENTIALS_FILE = f"{STATE_DIR}/credentials.json"


def read_shell_config(path):
    result = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                try:
                    parsed = shlex.split(value)
                    result[key] = parsed[0] if parsed else ""
                except ValueError:
                    result[key] = value.strip("'\"")
    except FileNotFoundError:
        pass
    return result


CFG = read_shell_config(CONFIG_FILE)
SETUP_SSID = CFG.get("SETUP_SSID", "Dicaffeine-Setup")
SETUP_PASSPHRASE = CFG.get("SETUP_PASSPHRASE", "dicaffeine")
SETUP_GATEWAY = CFG.get("SETUP_GATEWAY", "192.168.44.1")
SETUP_PORT = int(CFG.get("SETUP_PORT", "80"))


def read_state():
    state = {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                try:
                    parsed = shlex.split(value)
                    state[key] = parsed[0] if parsed else ""
                except ValueError:
                    state[key] = value.strip("'\"")
    except FileNotFoundError:
        pass
    return state


def write_state_connecting(iface, target_ssid):
    os.makedirs(STATE_DIR, exist_ok=True)
    lines = [
        "WYSE_WIFI_SETUP_ACTIVE=1",
        "WYSE_WIFI_SETUP_CONNECTING=1",
        f"WYSE_WIFI_SETUP_SSID={shlex.quote(SETUP_SSID)}",
        f"WYSE_WIFI_SETUP_PASSPHRASE={shlex.quote(SETUP_PASSPHRASE)}",
        f"WYSE_WIFI_SETUP_GATEWAY={shlex.quote(SETUP_GATEWAY)}",
        f"WYSE_WIFI_SETUP_IFACE={shlex.quote(iface)}",
        f"WYSE_WIFI_SETUP_TARGET_SSID={shlex.quote(target_ssid)}",
        f"WYSE_WIFI_SETUP_STARTED={int(time.time())}",
        "",
    ]
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def unescape_nmcli(value):
    return value.replace("\\:", ":").replace("\\\\", "\\")


def get_networks():
    networks = []
    seen = set()

    try:
        with open(NETWORKS_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        lines = []

    for line in lines:
        line = line.rstrip("\n")
        if not line:
            continue

        parts = []
        current = []
        escaped = False
        for ch in line:
            if escaped:
                current.append(ch)
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == ":":
                parts.append("".join(current))
                current = []
            else:
                current.append(ch)
        parts.append("".join(current))

        ssid = unescape_nmcli(parts[0]).strip() if parts else ""
        signal = parts[1].strip() if len(parts) > 1 else ""
        security = parts[2].strip() if len(parts) > 2 else ""

        if not ssid or ssid in seen or ssid == SETUP_SSID:
            continue

        seen.add(ssid)
        networks.append((ssid, signal, security))

    networks.sort(
        key=lambda item: int(item[1] or "0") if item[1].isdigit() else 0,
        reverse=True,
    )
    return networks


def render_page(message=""):
    state = read_state()
    iface = state.get("WYSE_WIFI_SETUP_IFACE", "")
    error = state.get("WYSE_WIFI_SETUP_ERROR", "")
    networks = get_networks()

    options = []
    for ssid, signal, security in networks:
        label = f"{ssid}"
        meta = []
        if signal:
            meta.append(f"{signal}%")
        if security:
            meta.append(security)
        if meta:
            label += " — " + " / ".join(meta)

        options.append(
            f'<option value="{html.escape(ssid, quote=True)}">{html.escape(label)}</option>'
        )

    options_html = "\n".join(options)
    if not options_html:
        options_html = '<option value="">No scan results — type SSID below</option>'

    message_html = f'<div class="message">{html.escape(message)}</div>' if message else ""
    error_html = f'<div class="error">{html.escape(error)}</div>' if error else ""

    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Dicaffeine Wi-Fi Setup</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {{
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #111;
      color: #f5f5f5;
      margin: 0;
      padding: 2rem;
    }}
    main {{
      max-width: 520px;
      margin: 0 auto;
      background: #1d1d1d;
      border: 1px solid #333;
      border-radius: 16px;
      padding: 1.5rem;
      box-shadow: 0 12px 40px rgba(0,0,0,.45);
    }}
    h1 {{ margin-top: 0; font-size: 1.5rem; }}
    label {{ display: block; margin-top: 1rem; margin-bottom: .35rem; }}
    select, input {{
      box-sizing: border-box;
      width: 100%;
      padding: .75rem;
      border-radius: 10px;
      border: 1px solid #555;
      background: #050505;
      color: #fff;
      font-size: 1rem;
    }}
    button {{
      margin-top: 1.25rem;
      width: 100%;
      padding: .85rem;
      border: 0;
      border-radius: 10px;
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
    }}
    .hint {{ color: #bbb; font-size: .95rem; line-height: 1.4; }}
    .message {{
      background: #17351f;
      border: 1px solid #2a7d3a;
      padding: .75rem;
      border-radius: 10px;
      margin-bottom: 1rem;
    }}
    .error {{
      background: #3a1717;
      border: 1px solid #8d3333;
      padding: .75rem;
      border-radius: 10px;
      margin-bottom: 1rem;
    }}
    .small {{ font-size: .85rem; color: #aaa; }}
  </style>
</head>
<body>
<main>
  <h1>Dicaffeine Wi-Fi Setup</h1>
  {message_html}
  {error_html}
  <p class="hint">
    Choose the venue Wi-Fi network and enter its password. The setup hotspot will then close,
    and the Dicaffeine receiver will join the selected network.
  </p>

  <form method="post" action="/save">
    <label for="ssid_select">Detected networks</label>
    <select id="ssid_select" name="ssid_select">
      {options_html}
    </select>

    <label for="ssid_manual">Or type SSID manually</label>
    <input id="ssid_manual" name="ssid_manual" placeholder="SSID">

    <label for="password">Wi-Fi password</label>
    <input id="password" name="password" type="password" autocomplete="current-password">

    <input type="hidden" name="iface" value="{html.escape(iface, quote=True)}">

    <button type="submit">Save Wi-Fi and connect</button>
  </form>

  <p class="small">
    Setup hotspot: {html.escape(SETUP_SSID)}<br>
    Setup page: http://{html.escape(SETUP_GATEWAY)}/
  </p>
</main>
</body>
</html>"""


class ReuseHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def send_html(self, html_text, code=200):
        data = html_text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.send_html(render_page())

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        form = urllib.parse.parse_qs(raw)

        ssid_manual = form.get("ssid_manual", [""])[0].strip()
        ssid_select = form.get("ssid_select", [""])[0].strip()
        password = form.get("password", [""])[0]
        iface = form.get("iface", [""])[0].strip()

        ssid = ssid_manual or ssid_select

        if not ssid:
            self.send_html(render_page("SSID was empty. Please choose or type a Wi-Fi network."))
            return

        os.makedirs(STATE_DIR, exist_ok=True)

        with open(CREDENTIALS_FILE, "w", encoding="utf-8") as f:
            json.dump({"ssid": ssid, "password": password, "iface": iface}, f)

        os.chmod(CREDENTIALS_FILE, 0o600)
        write_state_connecting(iface, ssid)

        try:
            subprocess.run(["wyse-ndi-update-qr"], check=False)
        except FileNotFoundError:
            pass

        subprocess.Popen(
            ["systemctl", "start", "--no-block", "wyse-wifi-setup-apply.service"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        self.send_html(render_page(
            f"Trying to connect to {ssid}. This setup Wi-Fi will disappear shortly. "
            "Reconnect to the normal network and use the Dicaffeine overlay QR once it returns."
        ))


def main():
    server = ReuseHTTPServer(("0.0.0.0", SETUP_PORT), Handler)
    print(f"Listening on http://0.0.0.0:{SETUP_PORT}/ portal=http://{SETUP_GATEWAY}/", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
EOFPORTAL

sudo chmod +x /usr/local/bin/wyse-wifi-setup-portal

echo "== Installing setup checker =="

sudo tee /usr/local/bin/wyse-wifi-setup-check >/dev/null <<'EOFCHECK'
#!/usr/bin/env bash
set -euo pipefail

. /etc/default/wyse-wifi-setup

STATE_DIR="/run/wyse-wifi-setup"
STATE_FILE="${STATE_DIR}/state"

mkdir -p "$STATE_DIR"

if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE" || true
fi

now="$(date +%s)"
started="${WYSE_WIFI_SETUP_STARTED:-0}"

if [ "${WYSE_WIFI_SETUP_CONNECTING:-0}" = "1" ]; then
  age=$((now - started))

  if [ "$age" -lt 120 ]; then
    exit 0
  fi
fi

wifi_iface="$(
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
    awk -F: '$2=="wifi" && $1 != "" {print $1; exit}'
)"

wired_has_ip=false
wifi_has_normal_ip=false

while IFS=: read -r dev type state connection; do
  case "$type" in
    ethernet)
      if ip -4 addr show dev "$dev" scope global 2>/dev/null | grep -q 'inet '; then
        wired_has_ip=true
      fi
      ;;
    wifi)
      if [ "$connection" != "$SETUP_SSID" ] && [ "$connection" != "Hotspot" ]; then
        if ip -4 addr show dev "$dev" scope global 2>/dev/null | grep -q 'inet '; then
          wifi_has_normal_ip=true
        fi
      fi
      ;;
  esac
done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null)

if [ "$wired_has_ip" = true ] || [ "$wifi_has_normal_ip" = true ]; then
  if systemctl is-active --quiet wyse-wifi-setup-portal.service; then
    systemctl stop wyse-wifi-setup-portal.service || true
  fi

  rm -f "$STATE_FILE"

  if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
    wyse-ndi-update-qr || true
  fi

  wyse-dicaffeine-userctl start dicaffeine || true
  exit 0
fi

if [ -z "${wifi_iface:-}" ]; then
  {
    printf 'WYSE_WIFI_SETUP_ACTIVE=0\n'
    printf 'WYSE_WIFI_SETUP_ERROR=%q\n' "No_WiFi_adapter_found"
  } > "$STATE_FILE"

  if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
    wyse-ndi-update-qr || true
  fi

  exit 0
fi

if ! iw list 2>/dev/null | grep -q '^[[:space:]]*\* AP$'; then
  {
    printf 'WYSE_WIFI_SETUP_ACTIVE=0\n'
    printf 'WYSE_WIFI_SETUP_ERROR=%q\n' "WiFi_adapter_does_not_support_AP_mode"
    printf 'WYSE_WIFI_SETUP_IFACE=%q\n' "$wifi_iface"
  } > "$STATE_FILE"

  if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
    wyse-ndi-update-qr || true
  fi

  exit 0
fi

if systemctl is-active --quiet wyse-wifi-setup-portal.service; then
  exit 0
fi

{
  printf 'WYSE_WIFI_SETUP_ACTIVE=1\n'
  printf 'WYSE_WIFI_SETUP_CONNECTING=0\n'
  printf 'WYSE_WIFI_SETUP_SSID=%q\n' "$SETUP_SSID"
  printf 'WYSE_WIFI_SETUP_PASSPHRASE=%q\n' "$SETUP_PASSPHRASE"
  printf 'WYSE_WIFI_SETUP_GATEWAY=%q\n' "$SETUP_GATEWAY"
  printf 'WYSE_WIFI_SETUP_IFACE=%q\n' "$wifi_iface"
  printf 'WYSE_WIFI_SETUP_STARTED=%q\n' "$(date +%s)"
} > "$STATE_FILE"

if command -v wyse-ndi-update-qr >/dev/null 2>&1; then
  wyse-ndi-update-qr || true
fi

systemctl start wyse-wifi-setup-portal.service
EOFCHECK

sudo chmod +x /usr/local/bin/wyse-wifi-setup-check

echo "== Installing systemd units =="

sudo tee /etc/systemd/system/wyse-wifi-setup-portal.service >/dev/null <<'EOFPORTALSERVICE'
[Unit]
Description=Wyse native Wi-Fi setup portal
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=simple
ExecStartPre=/usr/local/bin/wyse-dicaffeine-userctl stop dicaffeine
ExecStartPre=/usr/local/bin/wyse-wifi-setup-ap-start
ExecStart=/usr/local/bin/wyse-wifi-setup-portal
ExecStopPost=/usr/local/bin/wyse-wifi-setup-ap-stop
Restart=no

[Install]
WantedBy=multi-user.target
EOFPORTALSERVICE

sudo tee /etc/systemd/system/wyse-wifi-setup-apply.service >/dev/null <<'EOFAPPLYSERVICE'
[Unit]
Description=Apply Wi-Fi credentials selected from Wyse setup portal
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wyse-wifi-setup-apply
EOFAPPLYSERVICE

sudo tee /etc/systemd/system/wyse-wifi-setup-check.service >/dev/null <<'EOFCHECKSERVICE'
[Unit]
Description=Check whether Wyse Wi-Fi setup portal is needed
After=NetworkManager.service
Requires=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wyse-wifi-setup-check
EOFCHECKSERVICE

sudo tee /etc/systemd/system/wyse-wifi-setup-check.timer >/dev/null <<'EOFCHECKTIMER'
[Unit]
Description=Periodically check whether Wi-Fi setup portal is needed

[Timer]
OnBootSec=20
OnUnitActiveSec=30
AccuracySec=5
Unit=wyse-wifi-setup-check.service

[Install]
WantedBy=timers.target
EOFCHECKTIMER

echo "== Disabling old WiFi Connect service if it exists =="

sudo systemctl disable --now wyse-wifi-connect.service 2>/dev/null || true

sudo systemctl daemon-reload
sudo systemctl enable --now wyse-wifi-setup-check.timer

echo "== Refreshing overlay QR =="
sudo /usr/local/bin/wyse-wifi-setup-check || true
wyse-ndi-update-qr || true

echo
echo "Native Wi-Fi setup portal installed."
echo
echo "Current state:"
cat /run/wyse-wifi-setup/state 2>/dev/null || echo "normal mode"
