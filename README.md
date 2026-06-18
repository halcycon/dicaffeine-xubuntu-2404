# Wyse 3040 NDI / Dicaffeine Projection Receiver Notes

## Purpose

This document records the working setup for using a Dell Wyse 3040 as a lightweight NDI projection receiver for church/projector use.

The target use case is:

```text
FreeShow / NDI source / NDI camera / other NDI sender
        ↓
Network
        ↓
Wyse 3040 running Xubuntu 24.04 + Dicaffeine/Yuri2
        ↓
Projector / HDMI / DisplayPort output
```

The final working approach uses the Dicaffeine web GUI for source selection and play/stop control, but overrides the actual Yuri player command so that playback uses a known-good SDL2/RGBA32 pipeline.

---

## Licensing Considerations
This project does not redistribute the NDI® runtime or SDK.

During installation, the helper script can download the NDI SDK for Linux from NDI's official download URL and install the required runtime library locally. Use of the NDI SDK/runtime is subject to NDI's licence terms.

NDI® is a registered trademark of Vizrt NDI AB.

## Hardware and OS

Tested on:

```text
Device: Dell Wyse 3040
OS: Xubuntu 24.04 minimal
Storage: 8 GB eMMC
User: ndi
Display output: HDMI/DisplayPort via Xfce desktop session
Network: Ethernet strongly preferred
```

The 8 GB storage is very tight. Avoid installing compilers, full development libraries, large browsers, Snap packages, and unnecessary desktop applications.

---

## Key Findings

### 1. Dicaffeine 22.04 GUI can be made to work on Xubuntu 24.04

The full Dicaffeine GUI package was from the Ubuntu 22.04/Jammy set, while the Yuri2/NDI packages were from the newer 24.04/Noble setup.

The result is a hybrid build:

```text
Xubuntu 24.04
Dicaffeine GUI package 0.7.4
Yuri2 2.8.0
NDI 6.2.1
libpistache0
dummy equivs package for over-broad Yuri2 dependencies
```

### 2. Yuri2 package declares development packages as runtime dependencies

The `yuri2.deb` declared dependencies such as:

```text
libboost-all-dev
libgl1-mesa-dev
libavcodec-dev
libavformat-dev
libavutil-dev
libjsoncpp-dev
```

Those are large development packages and are not desirable on an 8 GB Wyse 3040.

A dummy `equivs` package named:

```text
dicaffeine-compat-dummy
```

was created to satisfy those package dependencies, while the real runtime libraries were installed separately.

### 3. NDI 6 works, but compatibility symlinks are required

The NDI 6 package installs libraries under:

```text
/usr/local/lib/ndi/
```

The working compatibility links are:

```text
/usr/local/lib/libndi.so   -> /usr/local/lib/ndi/libndi.so.6.2.1
/usr/local/lib/libndi.so.5 -> /usr/local/lib/ndi/libndi.so.6.2.1
/usr/local/lib/libndi.so.6 -> /usr/local/lib/ndi/libndi.so.6.2.1
```

This allows software expecting `libndi.so`, `libndi.so.5`, or `libndi.so.6` to load the installed NDI 6 runtime.

### 4. The default Dicaffeine Play path was broken on this setup

Dicaffeine successfully saved source selections to:

```text
/etc/dicaffeine/player.json
```

but did not create:

```text
/tmp/yuri_config_player.xml
```

The default Dicaffeine service attempted to run:

```text
/usr/bin/yuri2 /tmp/yuri_config_player.xml
```

which failed because the XML file did not exist.

The error looked like:

```text
[XmlBuilder] Failed to load file /tmp/yuri_config_player.xml
[YURI2] failed to initialize application: Failed to load file /tmp/yuri_config_player.xml
```

`XmlBuilder` is not a missing standalone binary. It is Yuri2’s internal XML config loader.

### 5. The working video pipeline requires SDL2 and RGBA32

Plain Dicaffeine/Yuri playback produced a blank window for some sources.

The known-good manual pipeline is:

```bash
yuri_simple \
  "ndi_input[stream=\"SOURCE NAME\",format=rgba32]" \
  "convert[format=rgba32]" \
  "sdl2_window[resolution=1280x720,fullscreen=1]"
```

Important points:

```text
Use sdl2_window
Force NDI input to rgba32
Add convert[format=rgba32]
Use fullscreen=1
```

### 6. Source-side issues matter

The Wyse was capable of smooth FPS with a different NDI video source.

Low FPS from FreeShow appeared to be source-specific rather than a hard Wyse limitation.

For FreeShow, test:

```text
720p or 1080p output
25/30 fps
non-transparent output
simple visible test slide
same VLAN/subnet
wired receiver
```

---

## Installed Package Files

The repeatable install kit contains these local `.deb` files:

```text
~/wyse-ndi-kit/debs/dicaffeine.deb
~/wyse-ndi-kit/debs/ndi6.deb
~/wyse-ndi-kit/debs/pistache.deb
~/wyse-ndi-kit/debs/yuri2.deb
~/wyse-ndi-kit/debs/dicaffeine-compat-dummy_1.0_all.deb
```

The install kit is archived as:

```text
~/wyse-ndi-kit-xubuntu2404.tar.gz
```

---

## Important Runtime Packages

The target system needs the runtime packages, not the full development stack:

```bash
sudo apt install --no-install-recommends -y \
  curl \
  ca-certificates \
  openssh-server \
  avahi-daemon \
  libavahi-common3 \
  libavahi-client3 \
  libcap2-bin \
  libssl3 \
  libgl1 \
  libegl1 \
  libglu1-mesa \
  libavcodec60 \
  libavformat60 \
  libavutil58 \
  libswscale7 \
  libjsoncpp25 \
  libsdl2-2.0-0 \
  libsdl1.2debian \
  libboost-python1.83.0 \
  libboost-system1.83.0 \
  libboost-filesystem1.83.0 \
  libboost-program-options1.83.0 \
  libboost-thread1.83.0 \
  libboost-chrono1.83.0 \
  libboost-date-time1.83.0 \
  libboost-regex1.83.0 \
  libboost-iostreams1.83.0 \
  x11-xserver-utils \
  jq \
  python3
```

---

## Key Config Files

### Dicaffeine main config

```text
/etc/dicaffeine/dserver.json
```

Important final values:

```json
"player_config": "/etc/dicaffeine/player.json",
"yuri_binary": "/usr/local/bin/dicaffeine-yuri-player",
"yuri_pconfig": "/tmp/yuri_config_player.xml",
"yuri_pkill": "pkill -9 -f 'yuri_simple.*ndi_input|dicaffeine-yuri-player'",
"yuri_pre": "DISPLAY=:0 xset s off -dpms"
```

The crucial change is:

```json
"yuri_binary": "/usr/local/bin/dicaffeine-yuri-player"
```

This avoids the broken Dicaffeine-generated XML path and uses the working wrapper instead.

### Dicaffeine selected player/source config

```text
/etc/dicaffeine/player.json
```

Dicaffeine writes the selected source here.

The wrapper reads:

```json
"streams": [
  {
    "name": "SOURCE NAME"
  }
]
```

and uses that as the NDI source.

### Dicaffeine auth config

```text
/etc/dicaffeine/dauth.json
```

The service may log:

```text
Could not load auth config, generating default!
```

This normally means `dauth.json` is missing, unreadable, or invalid. It does not mean all Dicaffeine config is failing.

Check it with:

```bash
ls -l /etc/dicaffeine/dauth.json
python3 -m json.tool /etc/dicaffeine/dauth.json
```

### Dicaffeine user service

```text
/usr/share/systemd/user/dicaffeine.service
```

The service runs:

```text
/usr/bin/dserver -c /etc/dicaffeine/dserver.json
```

User override:

```text
~/.config/systemd/user/dicaffeine.service.d/override.conf
```

Working override:

```ini
[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/ndi/.Xauthority
Environment=NDI_PATH=/usr/local/lib/libndi.so
Environment=LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib
```

---

## Key Scripts

### Dicaffeine environment wrapper

Location:

```text
/usr/local/bin/dicaffeine-env
```

Purpose:

Sets NDI-related environment variables before running a command.

Typical contents:

```bash
#!/usr/bin/env bash
export NDI_PATH=/usr/local/lib/libndi.so
export LD_LIBRARY_PATH=/usr/local/lib/ndi_hx:/usr/local/lib/ndi:/usr/local/lib:${LD_LIBRARY_PATH:-}
exec "$@"
```

Usage:

```bash
dicaffeine-env yuri2 -I ndi_input
```

---

### Dicaffeine Yuri player wrapper

Location:

```text
/usr/local/bin/dicaffeine-yuri-player
```

Purpose:

This is the actual playback wrapper used by Dicaffeine.

It reads the selected source from:

```text
/etc/dicaffeine/player.json
```

and launches:

```bash
/usr/bin/yuri_simple \
  "ndi_input[stream=\"${SRC}\",format=rgba32]" \
  "convert[format=rgba32]" \
  "sdl2_window[resolution=1280x720,fullscreen=1]"
```

Dicaffeine starts this because `dserver.json` has:

```json
"yuri_binary": "/usr/local/bin/dicaffeine-yuri-player"
```

Logs are visible with:

```bash
journalctl -t dicaffeine-yuri-player -n 50 --no-pager
```

---

### List NDI sources

Location:

```text
~/bin/list-ndi-sources.sh
```

Purpose:

Lists visible NDI sources.

Usage:

```bash
~/bin/list-ndi-sources.sh
```

Expected output example:

```text
Found 1 devices
        Device DESKTOP-0OLUU21 (FreeShow NDI - Primary) with 1 configurations
        stream: DESKTOP-0OLUU21 (FreeShow NDI - Primary)
                address: 192.168.101.34:5961
```

---

### Manual fallback player

Location:

```text
~/bin/play-ndi-manual.sh
```

Purpose:

Bypasses Dicaffeine web GUI and directly plays a named NDI source.

Usage:

```bash
~/bin/play-ndi-manual.sh 'EXACT NDI SOURCE NAME'
```

Known-good pipeline:

```bash
yuri_simple \
  "ndi_input[stream=\"${SRC}\",format=rgba32]" \
  "convert[format=rgba32]" \
  "sdl2_window[resolution=1280x720,fullscreen=1]"
```

---

## Service Commands

Dicaffeine is a **user service**, not a system service.

Use:

```bash
systemctl --user status dicaffeine --no-pager
systemctl --user restart dicaffeine
systemctl --user stop dicaffeine
systemctl --user start dicaffeine
```

Do not use:

```bash
sudo systemctl restart dicaffeine
```

unless a separate system service has deliberately been created.

Enable lingering so the user service can run reliably:

```bash
sudo loginctl enable-linger ndi
```

Reload user services:

```bash
systemctl --user daemon-reload
```

View logs:

```bash
journalctl --user -u dicaffeine -n 100 --no-pager
journalctl -t dicaffeine-yuri-player -n 100 --no-pager
```

---

## Web GUI

Dicaffeine web GUI listens on:

```text
http://<wyse-ip>/
```

The port is configured in:

```text
/etc/dicaffeine/dserver.json
```

Default:

```json
"port": 80
```

Workflow:

```text
1. Open Dicaffeine web GUI.
2. Select visible NDI source.
3. Save config.
4. Press Play.
5. Dicaffeine writes /etc/dicaffeine/player.json.
6. Dicaffeine launches /usr/local/bin/dicaffeine-yuri-player.
7. Wrapper reads player.json and starts SDL2/RGBA32 Yuri pipeline.
8. Stop button kills yuri_simple via yuri_pkill.
```

---

## Screen Blanking / Locking

For projector appliance use, disable all screen blanking and locking.

Immediate commands:

```bash
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset s off
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset s noblank
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset -dpms
```

Persistent file:

```text
~/.xprofile
```

Contents:

```bash
#!/usr/bin/env bash
xset s off
xset s noblank
xset -dpms
```

Autostart entry:

```text
~/.config/autostart/disable-screen-blanking.desktop
```

Contents:

```ini
[Desktop Entry]
Type=Application
Name=Disable Screen Blanking
Comment=Disable projector screen blanking
Exec=sh -c 'xset s off; xset s noblank; xset -dpms'
Terminal=false
X-GNOME-Autostart-enabled=true
```

Xfce settings:

```bash
xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false
xfconf-query -c xfce4-screensaver -p /lock/enabled -n -t bool -s false
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/presentation-mode -n -t bool -s true
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -n -t int -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -n -t bool -s false
```

Check current X blanking status:

```bash
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset q | grep -Ei 'timeout|DPMS|Standby|Suspend|Off'
```

---

## Troubleshooting

### Check disk usage

```bash
df -h
sudo du -xhd1 / | sort -h
sudo du -xhd1 /usr /var /home 2>/dev/null | sort -h | tail -40
```

### Check biggest packages

```bash
dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n | tail -50
```

### Safe cleanup

```bash
sudo apt clean
sudo journalctl --vacuum-size=50M
rm -rf ~/.cache/thumbnails/*
```

Use caution with:

```bash
sudo apt autoremove --purge
```

Always simulate first:

```bash
sudo apt -s autoremove --purge
```

Do not proceed if it wants to remove:

```text
dicaffeine
yuri2
ndi
libpistache0
dicaffeine-compat-dummy
xubuntu-desktop-minimal
xfce4-session
xorg
lightdm
openssh-server
```

### Check Dicaffeine package state

```bash
dpkg -l | grep -Ei 'dicaffeine|yuri2|ndi|pistache|compat'
```

### Check Yuri dependencies

```bash
ldd /usr/bin/yuri2 | grep "not found" || echo "yuri2 OK"
ldd /usr/bin/yuri_simple | grep "not found" || echo "yuri_simple OK"

ldd /usr/lib/yuri2/yuri2.8_module_ndi.so | grep "not found" || echo "NDI module OK"
ldd /usr/lib/yuri2/yuri2.8_module_sdl2_window.so | grep "not found" || echo "SDL2 module OK"
```

### Check NDI libraries

```bash
sudo find -L /usr /usr/local -type f -name 'libndi.so*' -printf '%p\n' 2>/dev/null | sort
ldconfig -p | grep -i ndi
ls -l /usr/local/lib/libndi.so*
```

Expected:

```text
/usr/local/lib/libndi.so -> /usr/local/lib/ndi/libndi.so.6.2.1
/usr/local/lib/libndi.so.5 -> /usr/local/lib/ndi/libndi.so.6.2.1
/usr/local/lib/libndi.so.6 -> /usr/local/lib/ndi/libndi.so.6.2.1
```

### Check NDI source discovery

```bash
~/bin/list-ndi-sources.sh
```

or:

```bash
dicaffeine-env yuri2 -I ndi_input
```

If no sources are found:

```bash
systemctl status avahi-daemon --no-pager
ip -4 addr
ping -c 3 <source-ip>
```

NDI discovery generally expects the sender and receiver to be on the same subnet/VLAN unless NDI discovery is configured separately.

### Manual playback test

```bash
~/bin/play-ndi-manual.sh 'EXACT NDI SOURCE NAME'
```

This bypasses the web GUI.

### Check Dicaffeine web GUI service

```bash
systemctl --user status dicaffeine --no-pager
journalctl --user -u dicaffeine -n 100 --no-pager
```

### Check player wrapper logs

```bash
journalctl -t dicaffeine-yuri-player -n 100 --no-pager
```

### Check running processes

```bash
pgrep -af 'dserver|dicaffeine-yuri-player|yuri_simple|yuri2'
```

### Stop stuck player manually

```bash
pkill -9 -f 'yuri_simple.*ndi_input|dicaffeine-yuri-player'
```

### Check selected source

```bash
cat /etc/dicaffeine/player.json
```

The source name used by the wrapper is:

```json
"streams": [
  {
    "name": "SOURCE NAME"
  }
]
```

### Watch Dicaffeine saving config

```bash
sudo apt install --no-install-recommends -y inotify-tools

inotifywait -m /tmp /etc/dicaffeine \
  -e create,modify,delete,move,open,close_write
```

Expected when saving in the web GUI:

```text
/etc/dicaffeine/ OPEN player.json
/etc/dicaffeine/ MODIFY player.json
/etc/dicaffeine/ CLOSE_WRITE,CLOSE player.json
```

### Trace Dicaffeine process launches

Install:

```bash
sudo apt install --no-install-recommends -y strace
```

Trace:

```bash
PID="$(systemctl --user show dicaffeine -p MainPID --value)"

sudo strace -f -s 300 \
  -e trace=execve,openat,creat,write,rename,unlink \
  -p "$PID" \
  -o /tmp/dserver.trace
```

Inspect:

```bash
grep -Ei 'execve|yuri|XmlBuilder|yuri_config_player|player.json|/tmp|EACCES|ENOENT' \
  /tmp/dserver.trace | tail -300
```

This was used to confirm that Dicaffeine called:

```text
/usr/bin/yuri2 /tmp/yuri_config_player.xml
```

but did not create the XML first.

---

## Known Good Playback Command

For direct testing:

```bash
export DISPLAY=:0
export XAUTHORITY=/home/ndi/.Xauthority
export SRC='EXACT NDI SOURCE NAME'

dicaffeine-env yuri_simple \
  "ndi_input[stream=\"${SRC}\",format=rgba32]" \
  "convert[format=rgba32]" \
  "sdl2_window[resolution=1280x720,fullscreen=1]"
```

This is the canonical fallback command.

---

## Repeatable Install Process

On the working Wyse:

```bash
tar -czf ~/wyse-ndi-kit-xubuntu2404.tar.gz ~/wyse-ndi-kit
```

On a new Wyse:

```bash
tar -xzf wyse-ndi-kit-xubuntu2404.tar.gz
cd wyse-ndi-kit
./install-wyse-ndi.sh
sudo reboot
```

After reboot:

```bash
~/bin/list-ndi-sources.sh
```

Then open:

```text
http://<wyse-ip>/
```

Select the source, save, and press Play.

---

## Final Architecture

```text
Dicaffeine web GUI
        ↓
Saves selected source to /etc/dicaffeine/player.json
        ↓
Dicaffeine starts yuri_binary
        ↓
/usr/local/bin/dicaffeine-yuri-player
        ↓
Reads source name from player.json
        ↓
Runs:
  yuri_simple
    ndi_input[stream="...",format=rgba32]
    convert[format=rgba32]
    sdl2_window[resolution=1280x720,fullscreen=1]
        ↓
Projector display
```

---

## Practical Notes

- Use wired Ethernet for the Wyse whenever possible.
- Keep the sender and Wyse on the same VLAN/subnet initially.
- FreeShow low FPS may be source-side; test with another NDI video source to separate sender issues from receiver issues.
- Avoid deleting `linux-firmware` even though it is large.
- Remove Snap if present and unused.
- Avoid installing large browsers unless needed.
- Dicaffeine’s local web GUI is accessible remotely, so a local browser on the Wyse is optional.
- Keep the manual player script available as the emergency fallback.
- Keep a long HDMI cable or Miracast dongle as event-day backup.

---

## Emergency Commands

Restart Dicaffeine:

```bash
systemctl --user restart dicaffeine
```

List sources:

```bash
~/bin/list-ndi-sources.sh
```

Manual play:

```bash
~/bin/play-ndi-manual.sh 'EXACT NDI SOURCE NAME'
```

Kill stuck player:

```bash
pkill -9 -f 'yuri_simple.*ndi_input|dicaffeine-yuri-player'
```

Disable screen blanking immediately:

```bash
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset s off
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset s noblank
DISPLAY=:0 XAUTHORITY=/home/ndi/.Xauthority xset -dpms
```

Check logs:

```bash
journalctl --user -u dicaffeine -n 100 --no-pager
journalctl -t dicaffeine-yuri-player -n 100 --no-pager
```

Check disk:

```bash
df -h
```
