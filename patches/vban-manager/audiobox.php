<?php
include 'config.php';
include 'wyse-common.php';

$page = 'audiobox';
$defaults = wyse_load_defaults();
$slot = $defaults['AUDIOBOX_SLOT'] !== '' ? $defaults['AUDIOBOX_SLOT'] : '1';
$status = wyse_server_status($slot);
$current = wyse_read_server_args($slot);
$receiverIp = wyse_primary_ip();
$defaultPort = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';
$streamPlaceholder = 'Stream name (optional — auto-detected from packets)';
$streamValue = '';
if ($status === 'active' && !empty($current['s'])) {
    $streamValue = $current['s'];
}
$cachedStreams = wyse_load_scan_cache($defaultPort);
if ($streamValue === '' && is_array($cachedStreams) && !empty($cachedStreams[0]['stream'])) {
    $streamPlaceholder = 'Detected: ' . $cachedStreams[0]['stream'];
}

include 'top.php';
?>

<div class="col-12 wyse-page">
  <div class="wyse-hero">
    <h3>Dashboard</h3>
    <p class="wyse-muted mb-0">
      Receive VBAN audio on
      <strong><?php echo wyse_h($receiverIp !== '' ? $receiverIp : 'this device'); ?></strong>
      · UDP <?php echo wyse_h($defaultPort); ?>
    </p>
  </div>

  <div class="wyse-card" id="current-stream-card">
    <h5>Current stream</h5>
    <div id="current-stream-body">
      <?php if ($status === 'active' && isset($current['s'], $current['i'])) { ?>
        <p class="wyse-status-active mb-1">
          Playing <strong><?php echo wyse_h($current['s']); ?></strong>
          from <?php echo wyse_h($current['i']); ?>:<?php echo wyse_h(isset($current['p']) ? $current['p'] : $defaultPort); ?>
        </p>
        <a class="btn btn-danger btn-sm" href="disconnect.php?id=<?php echo wyse_h($slot); ?>">Stop</a>
      <?php } elseif ($status === 'activating') { ?>
        <p class="wyse-status-connecting mb-1">Connecting&hellip;</p>
        <?php $journal = wyse_service_journal($slot, 8); if ($journal !== '') { ?>
        <pre class="wyse-log-snippet"><?php echo wyse_h($journal); ?></pre>
        <?php } ?>
      <?php } elseif ($status === 'failed') { ?>
        <p class="wyse-status-failed mb-1">Connection failed</p>
        <pre class="wyse-log-snippet"><?php echo wyse_h(wyse_service_journal($slot, 8)); ?></pre>
        <a class="btn btn-outline-secondary btn-sm" href="server.php?id=<?php echo wyse_h($slot); ?>">View log</a>
      <?php } else { ?>
        <p class="wyse-status-stopped mb-0">Not connected</p>
      <?php } ?>
    </div>
  </div>

  <div class="wyse-card" id="audio-panel" style="<?php echo $status === 'active' ? '' : 'display:none;'; ?>">
    <h5>Volume</h5>
    <div class="wyse-signal-row">
      <span class="wyse-signal-badge" id="signal-badge">Checking audio path&hellip;</span>
      <div class="wyse-signal-track" aria-hidden="true">
        <div class="wyse-signal-fill" id="signal-fill"></div>
      </div>
    </div>
    <p class="wyse-muted wyse-signal-help" id="audio-panel-note">
      PipeWire on this device does not expose audio peak meters. The bar shows VBAN/Pulse activity, not loudness.
    </p>
    <div class="wyse-volume-controls">
      <div class="wyse-volume-row">
        <label for="stream-volume"><span>Stream volume</span><span id="stream-vol-label">100%</span></label>
        <input type="range" id="stream-volume" min="0" max="150" step="1" value="100">
      </div>
      <div class="wyse-volume-row">
        <label for="sink-volume"><span>Output volume</span><span id="sink-vol-label">100%</span></label>
        <input type="range" id="sink-volume" min="0" max="150" step="1" value="100">
      </div>
    </div>
  </div>

  <div class="wyse-card">
    <h5>Find streams on the network</h5>
    <p class="wyse-muted">
      Start VBAN output on the sender first, then scan. Stream names are read from packet headers.
    </p>
    <button id="scan-btn" class="btn btn-primary" type="button">Scan for streams</button>
    <div id="scan-progress" class="wyse-scan-progress wyse-muted mt-3">
      Listening for VBAN packets&hellip;
    </div>
    <ul id="scan-results" class="wyse-stream-list mt-3"></ul>
    <div id="scan-error" class="alert alert-warning mt-3" style="display:none;"></div>
  </div>

  <div class="wyse-card">
    <h5>Connect manually</h5>
    <p class="wyse-muted mb-2">Sender IP is required. Leave stream name blank to use the name from VBAN packets.</p>
    <form class="wyse-form-grid" method="get" action="connect.php">
      <input type="hidden" name="id" value="<?php echo wyse_h($slot); ?>">
      <div class="form-group mb-0">
        <label class="sr-only" for="sender">Sender IP</label>
        <input class="form-control" type="text" id="sender" name="sender"
               placeholder="Sender IP" required
               value="<?php echo wyse_h(isset($current['i']) ? $current['i'] : $defaults['VBAN_SENDER_IP']); ?>">
      </div>
      <div class="form-group mb-0">
        <label class="sr-only" for="stream">Stream name (optional)</label>
        <input class="form-control" type="text" id="stream" name="stream"
               placeholder="<?php echo wyse_h($streamPlaceholder); ?>"
               value="<?php echo wyse_h($streamValue); ?>">
      </div>
      <button class="btn btn-success" type="submit">Connect</button>
    </form>
  </div>
</div>

<script>
(function () {
  var slot = <?php echo json_encode($slot); ?>;
  var scanBtn = document.getElementById('scan-btn');
  var scanProgress = document.getElementById('scan-progress');
  var scanResults = document.getElementById('scan-results');
  var scanError = document.getElementById('scan-error');
  var currentBody = document.getElementById('current-stream-body');
  var audioPanel = document.getElementById('audio-panel');
  var defaultPort = <?php echo json_encode($defaultPort); ?>;
  var streamVolume = document.getElementById('stream-volume');
  var sinkVolume = document.getElementById('sink-volume');
  var streamVolLabel = document.getElementById('stream-vol-label');
  var sinkVolLabel = document.getElementById('sink-vol-label');
  var signalBadge = document.getElementById('signal-badge');
  var signalFill = document.getElementById('signal-fill');
  var signalHelp = document.getElementById('audio-panel-note');
  var isActive = <?php echo json_encode($status === 'active'); ?>;
  var volumeTimers = { stream: null, sink: null };
  var displayedActivity = 0;
  var audioPollMs = 3000;

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function updateSignal(data) {
    if (!signalBadge || !signalFill) return;

    var signal = data.signal || {};
    var target = typeof signal.activity === 'number' ? signal.activity : 0;
    displayedActivity = (displayedActivity * 0.65) + (target * 0.35);
    signalFill.style.width = Math.max(4, Math.round(displayedActivity * 100)) + '%';

    if (signal.stream_playing) {
      signalBadge.textContent = 'Playing in PulseAudio';
      signalBadge.className = 'wyse-signal-badge active';
    } else {
      signalBadge.textContent = 'Waiting for PulseAudio stream';
      signalBadge.className = 'wyse-signal-badge idle';
    }

    if (signalHelp) {
      if (signal.mode === 'packets') {
        signalHelp.textContent = 'VBAN packets detected on the network (' + signal.packets_per_second + '/s). Sliders change Pulse volume only.';
      } else if (signal.peaks_available) {
        signalHelp.textContent = 'Live audio levels from PipeWire.';
      } else {
        signalHelp.textContent = 'PipeWire does not expose peak meters here. The bar shows stream presence, not loudness. Sliders change Pulse volume.';
      }
    }
  }

  function updateVolumeLabels() {
    if (streamVolLabel && streamVolume) {
      streamVolLabel.textContent = streamVolume.value + '%';
    }
    if (sinkVolLabel && sinkVolume) {
      sinkVolLabel.textContent = sinkVolume.value + '%';
    }
  }

  function postVolume(action, percent) {
    var body = 'action=' + encodeURIComponent(action) + '&percent=' + encodeURIComponent(String(percent)) + '&id=' + encodeURIComponent(slot);
    return fetch('volume-api.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body
    }).then(function (response) { return response.json(); });
  }

  function debounceVolume(action, value, key) {
    if (volumeTimers[key]) {
      clearTimeout(volumeTimers[key]);
    }
    volumeTimers[key] = setTimeout(function () {
      postVolume(action, value).catch(function () {});
    }, 120);
  }

  function pollAudioStatus() {
    if (!isActive) return;
    fetch('audio-levels-api.php?id=' + encodeURIComponent(slot))
      .then(function (response) { return response.json(); })
      .then(function (data) {
        if (!data.ok) return;
        updateSignal(data);
        if (data.stream && streamVolume && document.activeElement !== streamVolume && data.stream.volume_percent != null) {
          streamVolume.value = String(data.stream.volume_percent);
        }
        if (data.sink && sinkVolume && document.activeElement !== sinkVolume && data.sink.volume_percent != null) {
          sinkVolume.value = String(data.sink.volume_percent);
        }
        updateVolumeLabels();
      })
      .catch(function () {});
  }

  function renderCurrent(data) {
    isActive = data.state === 'active';
    if (audioPanel) {
      audioPanel.style.display = isActive ? '' : 'none';
    }

    if (data.state === 'active' && data.stream && data.sender) {
      currentBody.innerHTML =
        '<p class="wyse-status-active mb-1">Playing <strong>' + escapeHtml(data.stream) + '</strong> from ' +
        escapeHtml(data.sender) + ':' + escapeHtml(String(data.port || defaultPort)) + '</p>' +
        '<a class="btn btn-danger btn-sm" href="disconnect.php?id=' + encodeURIComponent(slot) + '">Stop</a>';
      pollAudioStatus();
      return;
    }
    if (data.state === 'activating') {
      var html = '<p class="wyse-status-connecting mb-1">Connecting&hellip;</p>';
      if (data.journal) {
        html += '<pre class="wyse-log-snippet">' + escapeHtml(data.journal) + '</pre>';
      }
      currentBody.innerHTML = html;
      return;
    }
    if (data.state === 'failed') {
      currentBody.innerHTML =
        '<p class="wyse-status-failed mb-1">Connection failed</p>' +
        '<pre class="wyse-log-snippet">' + escapeHtml(data.journal || 'Check Advanced settings log.') + '</pre>' +
        '<a class="btn btn-outline-secondary btn-sm" href="server.php?id=' + encodeURIComponent(slot) + '">View log</a>';
      return;
    }
    currentBody.innerHTML = '<p class="wyse-status-stopped mb-0">Not connected</p>';
  }

  function pollStatus() {
    fetch('status-api.php?id=' + encodeURIComponent(slot))
      .then(function (response) { return response.json(); })
      .then(renderCurrent)
      .catch(function () {});
  }

  function renderResults(streams) {
    scanResults.innerHTML = '';
    if (!streams.length) {
      scanResults.innerHTML = '<li><span class="wyse-muted">No VBAN streams heard. Check VoiceMeeter is sending to this device.</span></li>';
      return;
    }

    streams.forEach(function (item) {
      var li = document.createElement('li');
      var meta = document.createElement('div');
      meta.className = 'wyse-stream-meta';
      meta.innerHTML = '<strong>' + escapeHtml(item.stream) + '</strong>' +
        '<span class="wyse-muted">from ' + escapeHtml(item.sender) + ':' + escapeHtml(String(item.port || defaultPort)) +
        (item.packets ? ' · ' + escapeHtml(String(item.packets)) + ' packets' : '') + '</span>';

      var form = document.createElement('form');
      form.method = 'get';
      form.action = 'connect.php';
      form.innerHTML =
        '<input type="hidden" name="id" value="' + escapeHtml(slot) + '">' +
        '<input type="hidden" name="sender" value="' + escapeHtml(item.sender) + '">' +
        '<input type="hidden" name="stream" value="' + escapeHtml(item.stream) + '">' +
        '<input type="hidden" name="port" value="' + escapeHtml(String(item.port || defaultPort)) + '">' +
        '<button class="btn btn-success btn-sm" type="submit">Connect</button>';

      li.appendChild(meta);
      li.appendChild(form);
      scanResults.appendChild(li);
    });
  }

  if (streamVolume) {
    streamVolume.addEventListener('input', function () {
      updateVolumeLabels();
      debounceVolume('set_stream', streamVolume.value, 'stream');
    });
  }
  if (sinkVolume) {
    sinkVolume.addEventListener('input', function () {
      updateVolumeLabels();
      debounceVolume('set_sink', sinkVolume.value, 'sink');
    });
  }

  scanBtn.addEventListener('click', function () {
    scanBtn.disabled = true;
    scanProgress.classList.add('active');
    scanError.style.display = 'none';
    scanResults.innerHTML = '';

    fetch('scan.php')
      .then(function (response) { return response.json(); })
      .then(function (data) {
        if (data.error) {
          scanError.textContent = data.error;
          scanError.style.display = 'block';
        }
        renderResults(data.streams || []);
        if (data.streams && data.streams.length) {
          var senderInput = document.getElementById('sender');
          var streamInput = document.getElementById('stream');
          if (senderInput && !senderInput.value) {
            senderInput.value = data.streams[0].sender;
          }
          if (streamInput && !streamInput.value) {
            streamInput.placeholder = 'Detected: ' + data.streams[0].stream;
          }
        }
      })
      .catch(function (err) {
        scanError.textContent = 'Scan request failed: ' + err;
        scanError.style.display = 'block';
      })
      .finally(function () {
        scanBtn.disabled = false;
        scanProgress.classList.remove('active');
      });
  });

  setInterval(pollStatus, 2500);
  setInterval(pollAudioStatus, audioPollMs);
  pollStatus();
  updateVolumeLabels();
  if (isActive) {
    pollAudioStatus();
  }
})();
</script>

<?php include 'bottom.php'; ?>
