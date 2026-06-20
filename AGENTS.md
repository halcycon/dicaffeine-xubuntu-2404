# AGENTS.md — Wyse 3040 NDI / VBAN Church AV Appliance

Guidance for AI agents working in this repository.

## What this project is

A repeatable install kit for turning a **Dell Wyse 3040** thin client (Xubuntu 24.04, user `ndi`, ~8 GB eMMC) into a lightweight **church AV appliance**:

| Mode | Purpose | Primary software |
|------|---------|------------------|
| **Setup / control** | Initial Wi‑Fi and venue network configuration | NetworkManager hotspot + local portal |
| **VBAN audio** | LAN audio feed (e.g. VoiceMeeter) | VBAN (`vban_receptor`) via PipeWire or ALSA |
| **Service video** | NDI projection during service | Dicaffeine + Yuri2 SDL2/RGBA32 pipeline |

**Design principle:** VBAN is **not** converted to NDI. VBAN handles LAN audio playback (AudioBox); Dicaffeine handles NDI video. **VBAN and Dicaffeine may run together** when audio goes through PipeWire/PulseAudio (typical case). Only stop PipeWire when using direct ALSA for VBAN.

Target operator: Adam Camp. Example hostname: `ndi-3040-01`.

---

## Repository layout

```text
install-wyse-ndi.sh              # Master installer (NDI/Dicaffeine base + optional add‑ons)
scripts/
  update-wyse-ndi.sh             # Wrapper: install-wyse-ndi.sh --update
  install-common-helpers.sh      # Shared /usr/local/bin helpers + config stubs
  merge-dicaffeine-config.sh     # Safe dserver.json key merge (update mode)
  install-ndi6-sdk.sh
  install-dicaffeine-theme.sh
  install-desktop-info-overlay.sh # Two Conky boxes: VBAN (upper) + NDI (lower)
  install-wifi-setup-portal-native.sh
  install-vban-manager-wyse.sh
bin/                             # Source for installed helpers (wyse-*-status, vban-box-*)
config/                          # Defaults installed to /etc/default/ if missing
patches/vban-manager/            # Maintained VBAN-manager overrides (not perl/sed in place)
debs/
README.md
cursor-vban-ndi-dicaffeine-corpus.md
```

**Not in repo (obsolete, do not re‑add):** `scripts/install-wifi-connect.sh`, `scripts/install-wifi-setup-portal.sh`.

---

## Update mode (existing Wyse boxes)

Apply kit fixes **without** reinstalling `.deb` packages or touching `player.json`:

```bash
cd ~/wyse-ndi-kit
git pull   # or copy updated kit
./scripts/update-wyse-ndi.sh
```

Or: `./install-wyse-ndi.sh --update`

**Update refreshes:** shared helpers, Conky overlays (NDI + VBAN), Wi‑Fi portal scripts/units, optional VBAN layer, safe `dserver.json` key merge.

**Update skips:** Dicaffeine/Yuri `.deb` installs, NDI symlinks, grub/modprobe workarounds.

**Environment:**

| Variable | Default | Meaning |
|----------|---------|---------|
| `INSTALL_VBAN` | `auto` | Update VBAN if already installed; `1` force install; `0` skip |
| `FORCE_VBAN_BUILD` | `0` | Rebuild `vban_receptor` on update |
| `RESTART_DICAFFEINE` | `0` | Restart dicaffeine after merge |

Existing `/etc/default/wyse-vban` and `/etc/default/wyse-wifi-setup` are **never overwritten** on update.

---

## Config files

| File | Purpose |
|------|---------|
| `/etc/default/wyse-vban` | VBAN sender IP, stream name, UDP port, manager bind/port |
| `/etc/default/wyse-wifi-setup` | Hotspot SSID, gateway `192.168.44.1`, QR directory |

---

## Desktop overlays

Two Conky panels at bottom-right:

1. **VBAN AudioBox** (upper) — `wyse-vban-status`: manager URL, local receive IP/UDP port, configured streams with sender IP:port
2. **Dicaffeine Receiver** (lower) — QR code + NDI status

---

## Operational modes (intended behaviour)

### Setup / control mode

- NetworkManager hotspot: SSID `Dicaffeine-Setup`, 2.4 GHz ch 6, WPA2
- Portal: `http://192.168.44.1/` (gateway from `install-wifi-setup-portal-native.sh`)
- Dicaffeine **stops** during setup, **restarts** after setup
- Minor known issue: portal does not auto‑open on phone (acceptable)

### VBAN audio (AudioBox)

- Sender: **VoiceMeeter** or other VBAN source on the LAN (port **6980**, stream name must match exactly, case‑sensitive)
- Receiver: `vban_receptor` from [quiniouben/vban](https://github.com/quiniouben/vban)
- Control UI: [VBAN-manager](https://github.com/VBAN-manager/VBAN-manager) **AudioBox** page on PHP built‑in server, port **8088**, user `ndi`, **no sudo**

Working Pulse/PipeWire example:

```bash
vban_receptor -i <LAPTOP_IP> -p 6980 -s Stream1 -b pulseaudio -d "VBAN AudioBox" -q 1
```

**Critical semantics:**

- `-i` = **sender laptop IP**, not `0.0.0.0`
- `-b pulseaudio` → `-d` is stream/client label, **not** hardware device
- `-b alsa` → `-d` is ALSA device (prefer `plughw:CARD=<name>,DEV=0` over numeric card IDs)
- Diagnose packets: `sudo tcpdump -ni any udp port 6980`

### Service NDI mode

- FreeSHOW or other NDI sender → Dicaffeine web GUI → `dicaffeine-yuri-player` wrapper → SDL2 fullscreen
- Dicaffeine user service with `DISPLAY=:0`, NDI env vars, linger enabled
- Canonical pipeline: `ndi_input[format=rgba32]` → `convert[format=rgba32]` → `sdl2_window[fullscreen=1]`

---

## Hardware and audio constraints

| Device | ALSA card | Notes |
|--------|-----------|-------|
| Wyse onboard analogue | card 0 `rt5672` | **Unreliable for production** — I/O errors, volume changes in pavucontrol can kill audio |
| Wyse HDMI/DP | card 1 | `plughw:1,0` is HDMI, **not** headphones |
| USB audio (pending) | TBD | **Intended production output** — test with `vban-box-audio-info` when hardware arrives |

- Direct ALSA requires stopping PipeWire first (`vban-box-stop-pipewire` / `vban-box-start-pipewire`)
- Stopping PipeWire may affect Dicaffeine audio routing — prefer Pulse backend for concurrent VBAN + NDI
- Prefer PipeWire for USB first; fall back to direct ALSA if PipeWire misbehaves

---

## Install flow

### Base NDI appliance (proven)

```bash
cd wyse-ndi-kit
./install-wyse-ndi.sh    # run as ndi with sudo available
sudo reboot
```

Optional VBAN layer on **fresh** install:

```bash
INSTALL_VBAN=1 ./install-wyse-ndi.sh
```

### Update existing box

```bash
cd wyse-ndi-kit
./scripts/update-wyse-ndi.sh
```

First-time VBAN on an existing NDI box:

```bash
sudo INSTALL_VBAN=1 ./scripts/update-wyse-ndi.sh
# or
sudo INSTALL_VBAN=1 ./scripts/install-vban-manager-wyse.sh
```

---

## Runtime architecture

```text
┌─────────────────────────────────────────────────────────────┐
│  User: ndi  (loginctl enable-linger)                        │
├─────────────────────────────────────────────────────────────┤
│  dicaffeine.service (user)     → NDI playback / web GUI :80 │
│  vban-manager-web.service      → PHP server :8088           │
│  vban@<id>.service (user)      → vban_receptor instances    │
│  wyse-wifi-setup (system)      → hotspot + portal when active│
└─────────────────────────────────────────────────────────────┘
```

**Security:** VBAN-manager has **no authentication**. Bind to trusted LAN only; do not expose to the internet. Consider binding to control subnet IP instead of `0.0.0.0`.

**No sudo at runtime:** Installer patches `action.php` to remove sudo and replaces `vban.sh` with user‑systemd version. Do **not** add `/etc/sudoers.d/vban-manager`.

---

## Agent working rules

### Preserve the stable base

- Do not break NetworkManager hotspot setup or Dicaffeine SDL2/RGBA32 wrapper
- Keep `install-wifi-setup-portal-native.sh`; never reintroduce obsolete Wi‑Fi scripts
- Verify master installer does not reference removed scripts before adding calls

### Change conservatively

- 8 GB storage is tight — avoid compilers, large dev packages, Snap, heavy browsers on the Wyse
- NDI `.deb` is proprietary and gitignored; use `install-ndi6-sdk.sh` or local `debs/`
- Prefer patch files or a fork over fragile repeated `perl -pi` edits to VBAN-manager
- `pkill` in Dicaffeine config is scoped: `yuri_simple.*ndi_input|dicaffeine-yuri-player` — do not broaden to `pkill -f dicaffeine`

### VBAN-manager audit points

When touching `scripts/install-vban-manager-wyse.sh`:

1. Runtime processes run as `ndi`, not root/www-data
2. User systemd units in `~/.config/systemd/user/`, not `/etc/systemd/system/`
3. `action.php` sudo removal matches upstream PHP (verify Perl regex or replace with explicit patch)
4. `/run/user/$UID` may be missing during unattended install — linger + reboot may be required
5. `vban.sh` arg parsing uses shell word splitting — **no spaces** in stream/device names until fixed
6. Idempotent git pull (no hard reset); local VBAN-manager changes need a patch strategy
7. `Restart=on-failure` on bad args/audio can loop — consider manual‑stop behaviour

### Mode switching

VBAN and NDI/Dicaffeine **do not** need mutual exclusion when using PipeWire. Avoid running direct-ALSA VBAN while Dicaffeine needs PipeWire unless you understand the audio routing impact.

Use `vban-box-stop-pipewire` / `vban-box-start-pipewire` only for direct ALSA VBAN tests.

## Diagnostics cheat sheet

```bash
# NDI
~/bin/list-ndi-sources.sh
systemctl --user status dicaffeine
journalctl -t dicaffeine-yuri-player -n 50

# VBAN
sudo tcpdump -ni any udp port 6980
systemctl --user status vban-manager-web.service   # as ndi
vban-box-audio-info

# Audio
cat /proc/asound/cards && aplay -l && pactl list short sinks
fuser -v /dev/snd/*

# Wi‑Fi setup
wyse-ndi-status
```

---

## Current status (2026‑06‑20)

**Done / proven**

- Dicaffeine + NDI 6 + SDL2/RGBA32 wrapper on Wyse 3040
- Native NetworkManager Wi‑Fi setup portal
- VBAN packets received; Pulse/PipeWire playback works briefly
- VBAN-manager installer drafted (`scripts/install-vban-manager-wyse.sh`)
- Onboard RT5672 deemed unsuitable for production

**Pending**

- USB audio device testing and final PipeWire vs ALSA choice
- VBAN-manager UI improvements (sender IP help, backend labels, USB presets, auth warnings)
- Repo sanity audit (corpus section 14 checklist)
- Wire VBAN install into master installer (optional flag)
- Mode switching scripts (`church-*-mode`)
- Integration of VBAN-manager with existing setup portal (if desired)

---

## Reference documents

| File | Use when |
|------|----------|
| `README.md` | Dicaffeine/NDI install details, troubleshooting, config paths |
| `cursor-vban-ndi-dicaffeine-corpus.md` | VBAN field findings, installer audit checklist, pitfalls, command snippets |

When answering audit questions from corpus §14, read the relevant scripts and report findings before making changes.
