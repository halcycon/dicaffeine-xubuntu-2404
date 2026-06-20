# Cursor Handover Corpus: Wyse 3040 NDI / Dicaffeine / VBAN / VBAN-manager Appliance

Generated: 2026-06-20  
User / target operator: Adam Camp  
Target device: Dell Wyse 3040 thin client, hostname observed as `ndi-3040-01`, user `ndi`  
Primary purpose: lightweight church AV appliance for NDI playback via Dicaffeine and pre-service audio via VBAN.

This document is intended to be pasted into Cursor so an AI agent can sanity-check the repository scripts and compare them against what was actually discovered during troubleshooting.

---

## 1. High-level intended behaviour

The Wyse 3040 should support two broad modes:

```text
Setup / control mode:
  - NetworkManager hotspot for initial Wi-Fi/control setup
  - local control/status portal
  - Dicaffeine can be stopped while setup is active

Pre-service audio mode:
  - VoiceMeeter on sending laptop sends VBAN audio over LAN
  - Wyse receives VBAN using quiniouben/vban `vban_receptor`
  - audio plays via headphone/line output, eventually via USB audio interface

Service NDI mode:
  - FreeSHOW or similar sends video over NDI
  - Dicaffeine plays the selected NDI source
  - Dicaffeine owns the screen/output during service
```

The current practical design is **not** to convert VBAN to NDI. VBAN is simpler and better for pre-service audio-only playback. Dicaffeine should remain the NDI player for service video.

---

## 2. Previously stable Wyse / Dicaffeine setup

From the previous Wyse 3040 work, the stable base setup was:

```text
Native NetworkManager-based setup
Hotspot SSID: Dicaffeine-Setup
Hotspot band/channel: 2.4 GHz, channel 6
Security: WPA2/CCMP
Portal: http://192.168.44.1/
Behaviour: Dicaffeine stops during setup and restarts after setup
```

Known minor issue:

```text
The portal page did not automatically pop open on the phone.
This was considered acceptable / not a blocker.
```

Scripts that were previously considered keepers:

```text
install-wyse-ndi.sh
scripts/install-ndi6-sdk.sh
scripts/install-dicaffeine-theme.sh
scripts/install-desktop-info-overlay.sh
scripts/install-wifi-setup-portal-native.sh
```

Scripts that were previously considered obsolete / removable:

```text
scripts/install-wifi-connect.sh
scripts/install-wifi-setup-portal.sh
```

Cursor should check the repo for these names and verify that the obsolete scripts are not still being called by the master installer.

---

## 3. Dicaffeine expectations

Dicaffeine is the NDI playback application on the Wyse.

Expected integration points:

```text
- It can be stopped for setup mode.
- It can be started for service NDI playback mode.
- It should take the foreground when it is actively playing.
- It should not fight with VBAN audio mode for audio devices.
```

Important repo audit points:

```text
- Check how Dicaffeine is launched.
- Check whether scripts use `pkill -f dicaffeine` safely or too broadly.
- Check whether Dicaffeine is started from a desktop/session context where SDL/display/audio work correctly.
- Check whether any script assumes HDMI audio when production audio may be via USB/headphone output.
- Check that any Dicaffeine auto-start and any VBAN auto-start do not conflict.
```

Potential future mode scripts should make VBAN and Dicaffeine mutually exclusive unless intentional mixing is added.

---

## 4. VBAN findings

The chosen open-source implementation is:

```text
https://github.com/quiniouben/vban
```

Relevant tool:

```text
vban_receptor
```

Important command semantics discovered during troubleshooting:

```text
-i <IP>              For vban_receptor, use the sender laptop IP, not 0.0.0.0.
-p <PORT>           VBAN UDP port, usually 6980.
-s <STREAM_NAME>    Must exactly match the VoiceMeeter outgoing VBAN stream name. Case-sensitive.
-b pulseaudio       Output to PulseAudio/PipeWire.
-b alsa             Output directly to ALSA.
-d with pulseaudio  Visible stream/client name only, not the output device.
-d with alsa        Actual ALSA playback device name.
```

Working example using Pulse/PipeWire:

```bash
vban_receptor \
  -i <LAPTOP_IP> \
  -p 6980 \
  -s Stream1 \
  -b pulseaudio \
  -d "VBAN AudioBox" \
  -q 1
```

The VBAN sender is VoiceMeeter on the laptop. VoiceMeeter must have:

```text
- VBAN globally enabled
- outgoing stream enabled
- destination IP set to the Wyse IP
- port 6980
- stream name matching `-s`
- sample rate / channel count matching expectations, ideally 48 kHz stereo for first tests
```

Useful network diagnostic:

```bash
sudo tcpdump -ni any udp port 6980
```

If packets are arriving, tcpdump will show the sender laptop IP. That is the IP to use with `vban_receptor -i`.

---

## 5. Wyse onboard audio findings

The built-in analogue output on the Wyse 3040 was problematic. Observed ALSA card layout:

```text
card 0 [rt5672]: SOF - sof-bytcht rt5672
  DellInc.-Wyse3040ThinClient--022RX4
  device 0: PCM (*)
  device 1: PCM Deep Buffer (*)

card 1 [Audio]: HdmiLpeAudio - Intel HDMI/DP LPE Audio
  device 0/1/2: HDMI/DP LPE Audio
```

Important correction:

```text
plughw:1,0 is HDMI/DP, not headphones.
The analogue headphone/speaker card is card 0, `rt5672`.
```

Pulse/PipeWire sink observed:

```text
alsa_output.platform-cht-bsw-rt5672.HiFi__hw_rt5672__sink
Description: Built-in Audio Headphones + Stereo Speakers
Active Port: [Out] Headphones
```

The following showed the analogue card was held by PipeWire:

```text
/dev/snd/controlC0: pipewire, wireplumber
/dev/snd/pcmC0D0p: pipewire
/dev/snd/pcmC0D0c: pipewire
```

Stopping PipeWire released card 0 for direct ALSA testing:

```bash
systemctl --user stop pipewire-pulse.service pipewire-pulse.socket
systemctl --user stop wireplumber.service
systemctl --user stop pipewire.service pipewire.socket
```

Restarting PipeWire:

```bash
systemctl --user start pipewire.socket pipewire.service
systemctl --user start pipewire-pulse.socket pipewire-pulse.service
systemctl --user start wireplumber.service
```

Observed failure with direct ALSA and onboard RT5672 after running for a while:

```text
Error: alsa_write: short write (expected 103, wrote 6)
Error: alsa_write: snd_pcm_writei failed: Input/output error
Error: alsa_write: snd_pcm_recover failed: Input/output error
```

Also observed behaviour:

```text
- VBAN via Pulse/PipeWire worked briefly/beautifully.
- Changing the vban stream volume in pavucontrol caused all audio to stop.
- The pavucontrol output meter froze.
- Direct ALSA to the onboard device later failed with continuous tone and repeated I/O errors.
```

Conclusion:

```text
Do not trust the Wyse 3040 onboard RT5672 analogue output for production.
Use a class-compliant USB audio output/interface.
```

---

## 6. USB audio plan

Pending hardware: USB audio device / interface.

Likely expectation:

```text
USB Audio Class device + PipeWire = probably fine
USB Audio Class device + direct ALSA = fallback / likely robust
Wyse onboard rt5672 = avoid for production
```

When the USB audio device arrives, run:

```bash
cat /proc/asound/cards
aplay -l
pactl list short sinks
vban-box-audio-info
```

First try Pulse/PipeWire:

```bash
pavucontrol
paplay /usr/share/sounds/alsa/Front_Center.wav

vban_receptor \
  -i <LAPTOP_IP> \
  -p 6980 \
  -s Stream1 \
  -b pulseaudio \
  -d "VBAN AudioBox" \
  -q 1
```

If PipeWire misbehaves with the USB audio device, use direct ALSA:

```bash
speaker-test -D plughw:CARD=<USB_CARD>,DEV=0 -c 2 -t sine -f 440 -l 1

vban_receptor \
  -i <LAPTOP_IP> \
  -p 6980 \
  -s Stream1 \
  -b alsa \
  -d "plughw:CARD=<USB_CARD>,DEV=0" \
  -q 1
```

Prefer card-name syntax over numeric card numbers if stable:

```text
plughw:CARD=<USB_CARD>,DEV=0
```

rather than:

```text
plughw:2,0
```

because USB/card ordering may change.

---

## 7. VBAN-manager goal

The user wants to run:

```text
https://github.com/VBAN-manager/VBAN-manager
```

on the same NDI/VBAN Wyse box, so streams can be controlled from a lightweight web UI.

Requirements / preferences:

```text
- VERY lightweight HTTP server.
- Avoid Apache.
- Avoid nginx/lighttpd unless PHP built-in server proves unsuitable.
- Prefer PHP CLI built-in web server on port 8088.
- Keep everything user-level as `ndi`.
- Do not use sudo for starting/stopping VBAN streams.
- Do not install a sudoers rule for VBAN-manager.
```

Reason sudo is not desired:

```text
vban_receptor already runs successfully as user `ndi`.
The upstream VBAN-manager sudo model exists because it expected Apache/www-data controlling system services.
For this appliance, the PHP server, manager scripts, systemd user services, and VBAN processes can all run as `ndi`.
```

Important security caveat:

```text
VBAN-manager appears old and unauthenticated by default.
Keep it on trusted LAN/control network only.
Do not expose it directly to the public internet.
```

---

## 8. Generated install script to audit

A first-pass installer was generated as:

```text
/mnt/data/install-vban-manager-wyse.sh
```

If copied into the repo, likely name:

```text
install-vban-manager-wyse.sh
```

Intended usage:

```bash
sudo APP_USER=ndi WEB_PORT=8088 bash install-vban-manager-wyse.sh
```

The script currently intends to:

```text
- install packages:
  ca-certificates git curl
  build-essential autoconf automake libtool pkg-config
  libasound2-dev libpulse-dev alsa-utils
  php-cli

- clone/update quiniouben/vban into /opt/vban
- build vban using ./autogen.sh, ./configure --disable-jack, make, make install
- clone/update VBAN-manager into /opt/vban-manager
- chown relevant trees to APP_USER
- patch action.php to remove sudo
- replace script/vban.sh with a user-systemd-aware version
- create user-level systemd unit ~/.config/systemd/user/vban@.service
- create user-level systemd unit ~/.config/systemd/user/vban-manager-web.service
- enable linger for APP_USER
- start user@UID service
- enable/start vban-manager-web.service
- install helpers:
  /usr/local/bin/vban-box-audio-info
  /usr/local/bin/vban-box-stop-pipewire
  /usr/local/bin/vban-box-start-pipewire
```

Current important installer assumptions:

```text
APP_USER defaults to `ndi`.
WEB_PORT defaults to 8088.
INSTALL_BASE defaults to /opt.
BIND_ADDR defaults to 0.0.0.0.
VBAN_DIR defaults to /opt/vban.
MANAGER_DIR defaults to /opt/vban-manager.
```

---

## 9. Installer script audit checklist for Cursor

Please inspect any installer / repo scripts against this checklist.

### 9.1 Root vs user boundary

The install script can run as root for package install and writing `/opt` / `/usr/local/bin`, but runtime processes should be user-level:

```text
- PHP web UI runs as `ndi`.
- VBAN-manager files are owned by `ndi`.
- vban_receptor runs as `ndi`.
- vban@.service is a user service, not a system service.
- no `/etc/sudoers.d/vban-manager` should be created.
- no `sudo` should remain in VBAN-manager action path.
```

Check whether the patched `action.php` reliably removes sudo. The generated installer currently uses a Perl substitution:

```bash
perl -0pi -e 's/"sudo "\s*\.\s*\$command/\$command/g; s/sudo\s+\.\s*\$command/\$command/g' action.php
```

Cursor should verify this matches the actual upstream PHP code. If brittle, replace with an explicit patch or a small maintained fork/patch file.

### 9.2 User systemd environment

The script attempts to run `systemctl --user` via:

```bash
sudo -u "${APP_USER}" XDG_RUNTIME_DIR="/run/user/${APP_UID}" systemctl --user ...
```

Check for issues:

```text
- Is /run/user/$APP_UID present during unattended install?
- Is `loginctl enable-linger ndi` sufficient before starting services?
- Does `systemctl start user@$APP_UID.service` behave correctly on the target distro?
- Would a reboot be needed before the web service starts reliably?
```

The script prints a warning if `/run/user/$APP_UID` does not exist. Cursor should consider whether to make this more robust.

### 9.3 VBAN-manager `vban.sh` replacement

The generated replacement script supports:

```text
start
start-service
args
remove
stop
status
is-active
plugin
```

It stores args in:

```text
/opt/vban-manager/script/args-<id>.txt
```

Known limitation:

```text
The replacement currently uses simple shell word splitting:
read -r -a argv <<< "${args}"
This deliberately does not support spaces inside stream/device names.
```

Cursor should check whether VBAN-manager UI ever stores names/devices with spaces. If so, either:

```text
- encode args as JSON and parse safely, or
- constrain UI fields to no spaces, or
- quote/escape args robustly without introducing shell injection risk.
```

### 9.4 Service template

Generated user unit:

```ini
[Unit]
Description=VBAN stream %i
After=default.target

[Service]
Type=simple
WorkingDirectory=/opt/vban-manager/script
ExecStart=/bin/bash /opt/vban-manager/script/vban.sh start-service %i
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

Cursor should check:

```text
- Whether `%i` is enough or `%I` is needed for escaped instance names.
- Whether VBAN-manager stream IDs are safe as systemd instance names.
- Whether stream processes should restart on failure or stay stopped after manual stop.
- Whether `Restart=on-failure` causes undesirable restart loops for bad args/audio devices.
```

### 9.5 PHP built-in server

Generated user unit:

```ini
[Service]
WorkingDirectory=/opt/vban-manager
ExecStart=/usr/bin/php -S 0.0.0.0:8088 -t /opt/vban-manager
Restart=on-failure
RestartSec=2
```

Cursor should check:

```text
- Whether binding 0.0.0.0 is appropriate or should bind only to the control subnet/IP.
- Whether an auth layer is needed before production.
- Whether the PHP built-in server is adequate for single-user LAN control.
- Whether static assets and PHP routing work correctly with `-t /opt/vban-manager`.
```

### 9.6 Repeated install safety

Check idempotency:

```text
- Existing /opt/vban git repo: fetch/pull only, no hard reset.
- Existing /opt/vban-manager git repo: fetch/pull only, no hard reset.
- This protects local changes but may also leave outdated/patched files.
- action.php is backed up each run with timestamp.
- script/vban.sh is overwritten each run.
```

Cursor should decide whether future local modifications to VBAN-manager should live in:

```text
- a fork,
- a patch directory applied by the installer,
- or repo-local managed files copied over upstream.
```

If the user plans to modify VBAN-manager, a fork or patchset is probably cleaner than repeated sed/perl edits.

### 9.7 Audio helper commands

Generated helpers:

```bash
vban-box-audio-info
vban-box-stop-pipewire
vban-box-start-pipewire
```

Cursor should check:

```text
- These helpers are useful for diagnostics, but should mode switching call them automatically?
- If USB audio works through PipeWire, avoid stopping PipeWire unnecessarily.
- If using direct ALSA, stop PipeWire before opening the ALSA device.
- Starting/stopping PipeWire may affect Dicaffeine; mode scripts need clear ownership.
```

---

## 10. Suggested future repo structure

Potential clean structure:

```text
install-wyse-ndi.sh
scripts/
  install-ndi6-sdk.sh
  install-dicaffeine-theme.sh
  install-desktop-info-overlay.sh
  install-wifi-setup-portal-native.sh
  install-vban.sh
  install-vban-manager.sh
  install-audio-helpers.sh
  install-mode-scripts.sh
  patches/
    vban-manager/
      action-no-sudo.patch
      user-systemd-vban-sh.patch
      user-service-units/
        vban@.service
        vban-manager-web.service
bin/
  church-vban-mode
  church-ndi-mode
  church-idle-mode
  vban-box-audio-info
  vban-box-stop-pipewire
  vban-box-start-pipewire
```

Suggested mode scripts:

```text
church-vban-mode:
  - stop Dicaffeine
  - choose VBAN backend based on config
  - if direct ALSA, stop PipeWire first
  - run/start selected VBAN stream

church-ndi-mode:
  - stop VBAN streams
  - ensure PipeWire is running if Dicaffeine needs it
  - start/foreground Dicaffeine

church-idle-mode:
  - stop VBAN streams
  - stop/leave Dicaffeine as desired
  - show local status/portal
```

---

## 11. VBAN-manager changes likely to be needed

The user said they will have changes to make to VBAN-manager.

Likely useful changes:

```text
- Remove upstream sudo assumptions cleanly.
- Make backend choices explicit:
  pulseaudio / alsa / pipe / file
- For PulseAudio backend, label `-d` as stream name, not output device.
- For ALSA backend, label `-d` as ALSA device.
- Add field/help text for `-i` explaining it should be the sender IP, not 0.0.0.0.
- Add preset for VoiceMeeter / pre-service audio:
  receptor -i <sender-ip> -p 6980 -s Stream1 -b pulseaudio -d "VBAN AudioBox"
- Add safe USB ALSA preset once USB card name is known:
  receptor -i <sender-ip> -p 6980 -s Stream1 -b alsa -d plughw:CARD=<USB_CARD>,DEV=0
- Avoid accepting device/stream names with spaces unless argument escaping is fixed.
- Add visible warnings for unauthenticated LAN-only control.
- Add start/stop/status buttons that call user-level systemd services.
- Add diagnostics view showing:
  cat /proc/asound/cards
  aplay -l
  pactl list short sinks
  fuser -v /dev/snd/*
```

---

## 12. Important command snippets

### Build/install `vban` manually

```bash
sudo apt update
sudo apt install -y \
  git build-essential autoconf automake libtool pkg-config \
  libasound2-dev libpulse-dev alsa-utils

sudo git clone https://github.com/quiniouben/vban.git /opt/vban
sudo chown -R ndi:ndi /opt/vban
cd /opt/vban
./autogen.sh
./configure --disable-jack
make
sudo make install
```

### Start VBAN via Pulse/PipeWire

```bash
vban_receptor \
  -i <LAPTOP_IP> \
  -p 6980 \
  -s Stream1 \
  -b pulseaudio \
  -d "VBAN AudioBox" \
  -q 1
```

### Start VBAN via direct ALSA, USB example

```bash
vban_receptor \
  -i <LAPTOP_IP> \
  -p 6980 \
  -s Stream1 \
  -b alsa \
  -d "plughw:CARD=<USB_CARD>,DEV=0" \
  -q 1
```

### Audio diagnostics

```bash
cat /proc/asound/cards
aplay -l
aplay -L | grep -A3 -iE 'usb|uac|audio|rt5672|default|sysdefault|plughw|hw'
pactl list short sinks
pactl list sinks | grep -E 'Name:|Description:|Active Port:'
fuser -v /dev/snd/*
```

### Stop PipeWire before direct ALSA

```bash
systemctl --user stop pipewire-pulse.service pipewire-pulse.socket || true
systemctl --user stop wireplumber.service || true
systemctl --user stop pipewire.service pipewire.socket || true
```

### Restart PipeWire

```bash
systemctl --user start pipewire.socket pipewire.service || true
systemctl --user start pipewire-pulse.socket pipewire-pulse.service || true
systemctl --user start wireplumber.service || true
```

---

## 13. Known pitfalls to keep in the repo comments/docs

```text
- `vban_receptor -i 0.0.0.0` was wrong for this implementation; use sender IP.
- Stream name must exactly match VoiceMeeter.
- With `-b pulseaudio`, `-d` is not the hardware output device.
- With `-b alsa`, `-d` is the hardware/logical ALSA device.
- Wyse onboard card 0 is rt5672 analogue; card 1 is HDMI/DP.
- Wyse onboard rt5672 analogue path is unreliable; USB audio recommended.
- Direct ALSA needs PipeWire/Pulse stopped if they hold the device.
- VBAN-manager upstream assumes Apache/www-data/sudo/system services; this appliance should not.
- Keep VBAN-manager local/trusted only unless authentication is added.
- Avoid spaces in generated VBAN arg strings until argument handling is made robust.
```

---

## 14. Desired Cursor task

Cursor should review the repository and answer:

```text
1. Do the scripts implement the intended stable Wyse setup?
2. Are obsolete Wi-Fi/setup scripts still referenced anywhere?
3. Does the VBAN-manager installer avoid sudo at runtime?
4. Are systemd user services used correctly for `ndi`?
5. Are PipeWire and direct ALSA mode transitions safe and reversible?
6. Does the repo clearly separate:
   - setup mode
   - VBAN audio mode
   - Dicaffeine NDI mode
7. Are assumptions about audio devices documented and configurable?
8. Is the USB audio path easy to configure when the device arrives?
9. Are there any dangerous broad `pkill` commands?
10. Are local changes to VBAN-manager managed as a patch/fork rather than fragile sed edits?
11. Is the control web UI protected from accidental public exposure?
12. Is Dicaffeine startup/foregrounding still compatible with these changes?
```

Cursor should make changes conservatively, preserving the known-good NetworkManager/Dicaffeine base and adding VBAN/VBAN-manager as a clearly separate layer.

---

## 15. Current status summary

```text
DONE / proven:
  - VBAN packets received from VoiceMeeter when using correct sender IP.
  - VBAN stream appears in pavucontrol with Pulse backend.
  - VBAN audio played through the Wyse briefly with Pulse/PipeWire.
  - Direct ALSA can access card 0 once PipeWire releases it.
  - Onboard RT5672 audio is unstable under both Pulse/PipeWire and direct ALSA.
  - A USB audio device/interface is the intended production fix.
  - VBAN-manager should be run lightweight via PHP built-in server as `ndi`.
  - No sudoers rule should be needed for VBAN-manager in this appliance design.

PENDING:
  - USB audio device testing.
  - Final choice between PipeWire and direct ALSA for USB audio.
  - VBAN-manager UI modifications.
  - Repo sanity-check and patch cleanup in Cursor.
  - Integration of VBAN-manager/control page with existing Wyse portal, if desired.
```
