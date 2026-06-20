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

include 'top.php';
?>

<link href="css/wyse-audiobox.css" rel="stylesheet">

<div class="col-md-8">
  <h3>VBAN AudioBox</h3>
  <p class="wyse-muted">
    Receive VBAN audio on this device. VoiceMeeter should send to
    <strong><?php echo wyse_h($receiverIp !== '' ? $receiverIp : 'this device'); ?></strong>
    on UDP port <strong><?php echo wyse_h($defaultPort); ?></strong>.
    Stream names are read from the VBAN packet header when you scan.
  </p>

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

  <div class="wyse-card">
    <h5>Find streams on the network</h5>
    <p class="wyse-muted">
      Start VBAN output on the sender first, then scan. Each VBAN audio packet carries the stream name in its header.
      Scanning briefly stops any active playback on this device.
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
    <p class="wyse-muted mb-2">Sender IP is required. Leave stream name blank to auto-detect it from incoming VBAN packets.</p>
    <form class="form-inline" method="get" action="connect.php">
      <input type="hidden" name="id" value="<?php echo wyse_h($slot); ?>">
      <div class="form-group mr-2 mb-2">
        <label class="sr-only" for="sender">Sender IP</label>
        <input class="form-control" type="text" id="sender" name="sender"
               placeholder="Sender IP" required
               value="<?php echo wyse_h(isset($current['i']) ? $current['i'] : $defaults['VBAN_SENDER_IP']); ?>">
      </div>
      <div class="form-group mr-2 mb-2">
        <label class="sr-only" for="stream">Stream name (optional)</label>
        <input class="form-control" type="text" id="stream" name="stream"
               placeholder="Stream name (optional)"
               value="<?php echo wyse_h(isset($current['s']) ? $current['s'] : ''); ?>">
      </div>
      <button class="btn btn-success mb-2" type="submit">Connect</button>
    </form>
  </div>

  <p class="wyse-muted">
    <a href="settings.php">Settings</a>
    &middot;
    <a href="server.php?id=<?php echo wyse_h($slot); ?>">Advanced server</a>
  </p>
</div>

<script>
(function () {
  var slot = <?php echo json_encode($slot); ?>;
  var scanBtn = document.getElementById('scan-btn');
  var scanProgress = document.getElementById('scan-progress');
  var scanResults = document.getElementById('scan-results');
  var scanError = document.getElementById('scan-error');
  var currentBody = document.getElementById('current-stream-body');
  var defaultPort = <?php echo json_encode($defaultPort); ?>;

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function renderCurrent(data) {
    if (data.state === 'active' && data.stream && data.sender) {
      currentBody.innerHTML =
        '<p class="wyse-status-active mb-1">Playing <strong>' + escapeHtml(data.stream) + '</strong> from ' +
        escapeHtml(data.sender) + ':' + escapeHtml(String(data.port || defaultPort)) + '</p>' +
        '<a class="btn btn-danger btn-sm" href="disconnect.php?id=' + encodeURIComponent(slot) + '">Stop</a>';
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
  pollStatus();
})();
</script>

<?php include 'bottom.php'; ?>
