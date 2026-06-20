#!/usr/bin/env bash
set -euo pipefail

# Merge known-good Dicaffeine keys without touching player.json or unrelated settings.

TARGET_USER="${SUDO_USER:-${TARGET_USER:-$USER}}"

if [ "$TARGET_USER" = "root" ] && [ -z "${SUDO_USER:-}" ]; then
  echo "Run through sudo from the normal desktop user." >&2
  exit 1
fi

if [ ! -f /etc/dicaffeine/dserver.json ]; then
  echo "No /etc/dicaffeine/dserver.json; skipping merge."
  exit 0
fi

sudo python3 - <<'PY'
import json
from pathlib import Path

p = Path("/etc/dicaffeine/dserver.json")
data = json.loads(p.read_text())

expected = {
    "player_config": "/etc/dicaffeine/player.json",
    "yuri_binary": "/usr/local/bin/dicaffeine-yuri-player",
    "yuri_pconfig": "/tmp/yuri_config_player.xml",
    "yuri_pkill": "pkill -9 -f 'yuri_simple.*ndi_input|dicaffeine-yuri-player'",
    "yuri_pre": "DISPLAY=:0 xset s off -dpms",
}

changed = False
for key, value in expected.items():
    if data.get(key) != value:
        print(f"Updating dserver.json key: {key}")
        data[key] = value
        changed = True

if changed:
    backup = p.with_name(p.name + ".bak.merge")
    backup.write_text(p.read_text())
    p.write_text(json.dumps(data, indent=4) + "\n")
    print(f"Merged keys into {p} (backup: {backup})")
else:
    print("dserver.json already has expected Wyse kit keys.")
PY

sudo chown "$TARGET_USER:$TARGET_USER" /etc/dicaffeine/dserver.json 2>/dev/null || true
