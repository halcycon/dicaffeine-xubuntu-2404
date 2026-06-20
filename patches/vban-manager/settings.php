<?php
include 'config.php';
include 'wyse-common.php';

$page = 'settings';
$config = wyse_load_defaults();
$writable = wyse_config_writable();
$devices = wyse_list_audio_devices();

include 'top.php';
?>

<link href="css/wyse-audiobox.css" rel="stylesheet">

<div class="col-md-8">
  <h3>AudioBox settings</h3>
  <p class="wyse-muted">
    Stored in <code><?php echo wyse_h(wyse_config_path()); ?></code>.
    These defaults apply to Scan, Connect, and the desktop overlay.
  </p>

  <?php if (!$writable) { ?>
    <div class="alert alert-warning">
      Settings file is not writable. Run on the Wyse:
      <code>sudo chown root:ndi /etc/default/wyse-vban && sudo chmod 664 /etc/default/wyse-vban</code>
    </div>
  <?php } ?>

  <?php if (isset($_GET['error'])) { ?>
    <div class="alert alert-danger"><?php echo wyse_h(urldecode($_GET['error'])); ?></div>
  <?php } ?>

  <form method="post" action="save-settings.php" id="settings-form">
    <div class="wyse-card">
      <h5>Network</h5>
      <div class="form-group">
        <label for="VBAN_SENDER_IP">Default sender IP</label>
        <input class="form-control" name="VBAN_SENDER_IP" id="VBAN_SENDER_IP"
               value="<?php echo wyse_h($config['VBAN_SENDER_IP']); ?>"
               placeholder="e.g. 192.168.1.50">
        <small class="form-text text-muted">VoiceMeeter PC address (not 0.0.0.0).</small>
      </div>
      <div class="form-row">
        <div class="form-group col-md-4">
          <label for="VBAN_UDP_PORT">UDP port</label>
          <input class="form-control" name="VBAN_UDP_PORT" id="VBAN_UDP_PORT"
                 value="<?php echo wyse_h($config['VBAN_UDP_PORT']); ?>">
        </div>
        <div class="form-group col-md-4">
          <label for="VBAN_STREAM_NAME">Fallback stream name</label>
          <input class="form-control" name="VBAN_STREAM_NAME" id="VBAN_STREAM_NAME"
                 value="<?php echo wyse_h($config['VBAN_STREAM_NAME']); ?>">
          <small class="form-text text-muted">Advanced UI and overlay only. Connect uses names from VBAN packets.</small>
        </div>
        <div class="form-group col-md-4">
          <label for="VBAN_SCAN_SECONDS">Scan seconds</label>
          <input class="form-control" name="VBAN_SCAN_SECONDS" id="VBAN_SCAN_SECONDS"
                 value="<?php echo wyse_h($config['VBAN_SCAN_SECONDS']); ?>">
        </div>
      </div>
      <div class="form-group">
        <label for="VBAN_NETWORK_QUALITY">Network quality (-q)</label>
        <select class="form-control" name="VBAN_NETWORK_QUALITY" id="VBAN_NETWORK_QUALITY">
          <?php foreach (array('0', '1', '2', '3', '4') as $q) { ?>
            <option value="<?php echo wyse_h($q); ?>" <?php echo $config['VBAN_NETWORK_QUALITY'] === $q ? 'selected' : ''; ?>>
              <?php echo wyse_h($q); ?><?php echo $q === '1' ? ' (default)' : ''; ?>
            </option>
          <?php } ?>
        </select>
      </div>
    </div>

    <div class="wyse-card">
      <h5>Audio output</h5>
      <div class="form-group">
        <label for="VBAN_BACKEND">Backend</label>
        <select class="form-control" name="VBAN_BACKEND" id="VBAN_BACKEND">
          <option value="pulseaudio" <?php echo $config['VBAN_BACKEND'] === 'pulseaudio' ? 'selected' : ''; ?>>
            PipeWire / PulseAudio (recommended)
          </option>
          <option value="alsa" <?php echo $config['VBAN_BACKEND'] === 'alsa' ? 'selected' : ''; ?>>
            Direct ALSA
          </option>
        </select>
      </div>

      <div id="pulse-settings">
        <p class="wyse-muted">
          PipeWire status:
          <strong><?php echo !empty($devices['pipewire_running']) ? 'running' : 'not running'; ?></strong>.
          VBAN and NDI can share audio this way.
        </p>
        <div class="form-group">
          <label for="VBAN_PULSE_LABEL">Pulse stream label</label>
          <input class="form-control" name="VBAN_PULSE_LABEL" id="VBAN_PULSE_LABEL"
                 value="<?php echo wyse_h($config['VBAN_PULSE_LABEL']); ?>">
          <small class="form-text text-muted">Shown in pavucontrol; this is not the hardware device.</small>
        </div>
        <div class="form-group">
          <label for="VBAN_PULSE_SINK">Output sink</label>
          <select class="form-control" name="VBAN_PULSE_SINK" id="VBAN_PULSE_SINK">
            <option value="">System default<?php echo !empty($devices['pulse_default_sink']) ? ' (' . wyse_h($devices['pulse_default_sink']) . ')' : ''; ?></option>
            <?php foreach ($devices['pulse_sinks'] as $sink) { ?>
              <option value="<?php echo wyse_h($sink['name']); ?>"
                <?php echo $config['VBAN_PULSE_SINK'] === $sink['name'] ? 'selected' : ''; ?>>
                <?php echo wyse_h($sink['description']); ?><?php echo !empty($sink['default']) ? ' (current default)' : ''; ?>
              </option>
            <?php } ?>
          </select>
          <small class="form-text text-muted">Applied with <code>pactl set-default-sink</code> before Connect.</small>
        </div>
        <button type="button" class="btn btn-outline-secondary btn-sm" id="refresh-devices">Refresh device list</button>
      </div>

      <div id="alsa-settings" style="display:none;">
        <div class="alert alert-info py-2">
          Direct ALSA bypasses PipeWire. Wyse onboard audio (rt5672) is unreliable; prefer USB.
        </div>
        <div class="form-group form-check">
          <input class="form-check-input" type="checkbox" name="VBAN_STOP_PIPEWIRE_FOR_ALSA" id="VBAN_STOP_PIPEWIRE_FOR_ALSA" value="1"
            <?php echo ($config['VBAN_STOP_PIPEWIRE_FOR_ALSA'] ?? '1') === '1' ? 'checked' : ''; ?>>
          <label class="form-check-label" for="VBAN_STOP_PIPEWIRE_FOR_ALSA">
            Stop PipeWire before starting VBAN (recommended for ALSA)
          </label>
        </div>
        <div class="form-group">
          <label for="VBAN_ALSA_DEVICE">ALSA playback device</label>
          <select class="form-control" name="VBAN_ALSA_DEVICE" id="VBAN_ALSA_DEVICE">
            <option value="">Select a device…</option>
            <?php foreach ($devices['alsa_cards'] as $card) { ?>
              <?php foreach ($card['devices'] as $dev) { ?>
                <option value="<?php echo wyse_h($dev['plughw']); ?>"
                  <?php echo $config['VBAN_ALSA_DEVICE'] === $dev['plughw'] ? 'selected' : ''; ?>>
                  [<?php echo wyse_h($card['id']); ?>] <?php echo wyse_h($dev['description']); ?> — <?php echo wyse_h($dev['plughw']); ?>
                </option>
              <?php } ?>
            <?php } ?>
          </select>
          <small class="form-text text-muted">Uses <code>plughw:CARD=…,DEV=0</code> style device names.</small>
        </div>
      </div>
    </div>

    <div class="wyse-card">
      <h5>Web UI</h5>
      <div class="form-row">
        <div class="form-group col-md-4">
          <label for="VBAN_MANAGER_PORT">Web port</label>
          <input class="form-control" name="VBAN_MANAGER_PORT" id="VBAN_MANAGER_PORT"
                 value="<?php echo wyse_h($config['VBAN_MANAGER_PORT']); ?>">
        </div>
        <div class="form-group col-md-8">
          <label for="VBAN_MANAGER_BIND">Bind address</label>
          <input class="form-control" name="VBAN_MANAGER_BIND" id="VBAN_MANAGER_BIND"
                 value="<?php echo wyse_h($config['VBAN_MANAGER_BIND']); ?>">
          <small class="form-text text-muted">Use a LAN IP instead of 0.0.0.0 to limit exposure. Restart <code>vban-manager-web.service</code> after changing port/bind.</small>
        </div>
      </div>
      <input type="hidden" name="VBAN_MANAGER_DIR" value="<?php echo wyse_h($config['VBAN_MANAGER_DIR']); ?>">
      <input type="hidden" name="AUDIOBOX_SLOT" value="<?php echo wyse_h($config['AUDIOBOX_SLOT']); ?>">
    </div>

    <button type="submit" class="btn btn-primary" <?php echo $writable ? '' : 'disabled'; ?>>Save settings</button>
    <a class="btn btn-link" href="audiobox.php">Back to AudioBox</a>
  </form>
</div>

<script>
(function () {
  var backend = document.getElementById('VBAN_BACKEND');
  var pulse = document.getElementById('pulse-settings');
  var alsa = document.getElementById('alsa-settings');
  var pulseSink = document.getElementById('VBAN_PULSE_SINK');
  var alsaDevice = document.getElementById('VBAN_ALSA_DEVICE');
  var refreshBtn = document.getElementById('refresh-devices');

  function toggleSections() {
    var usePulse = backend.value === 'pulseaudio';
    pulse.style.display = usePulse ? 'block' : 'none';
    alsa.style.display = usePulse ? 'none' : 'block';
  }

  function refillSelect(select, options, current) {
    select.innerHTML = '';
    options.forEach(function (opt) {
      var el = document.createElement('option');
      el.value = opt.value;
      el.textContent = opt.label;
      if (opt.value === current) {
        el.selected = true;
      }
      select.appendChild(el);
    });
  }

  refreshBtn.addEventListener('click', function () {
    fetch('audio-devices.php')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var sinkOptions = [{
          value: '',
          label: 'System default' + (data.pulse_default_sink ? ' (' + data.pulse_default_sink + ')' : '')
        }];
        (data.pulse_sinks || []).forEach(function (sink) {
          sinkOptions.push({
            value: sink.name,
            label: sink.description + (sink.default ? ' (current default)' : '')
          });
        });
        refillSelect(pulseSink, sinkOptions, pulseSink.value);

        var alsaOptions = [{ value: '', label: 'Select a device…' }];
        (data.alsa_cards || []).forEach(function (card) {
          (card.devices || []).forEach(function (dev) {
            alsaOptions.push({
              value: dev.plughw,
              label: '[' + card.id + '] ' + dev.description + ' — ' + dev.plughw
            });
          });
        });
        refillSelect(alsaDevice, alsaOptions, alsaDevice.value);
      });
  });

  backend.addEventListener('change', toggleSections);
  toggleSections();
})();
</script>

<?php include 'bottom.php'; ?>
