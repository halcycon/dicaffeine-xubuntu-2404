<?php
include 'config.php';
include 'wyse-common.php';

$page = 'server';
$defaults = wyse_load_defaults();

function after($needle, $haystack)
{
    if (!is_bool(strpos($haystack, $needle))) {
        return substr($haystack, strpos($haystack, $needle) + strlen($needle));
    }
    return '';
}

function before($needle, $haystack)
{
    return substr($haystack, 0, strpos($haystack, $needle));
}

$id = $_GET['id'];
$argsfile = wyse_args_path($id);

if (!isset($_GET['new'])) {
    $argscontent = file_get_contents($argsfile);
    $type = before(' ', $argscontent);
    $arguments = after(' ', $argscontent);

    preg_match_all('/-([a-z]) ([^ ]+) /', $arguments . ' ', $argsar);
    $argsParsed = array();
    for ($i = 0; $i < count($argsar[1]); $i++) {
        $argsParsed[$argsar[1][$i]] = $argsar[2][$i];
    }
} else {
    $type = 'receptor';
    $argsParsed = array(
        'p' => $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980',
        'b' => $defaults['VBAN_BACKEND'] !== '' ? $defaults['VBAN_BACKEND'] : 'pulseaudio',
        'd' => $defaults['VBAN_PULSE_LABEL'] !== '' ? $defaults['VBAN_PULSE_LABEL'] : 'VBAN AudioBox',
        'q' => '1',
        'l' => '1',
    );
}

$defaultPort = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';

include 'top.php';
?>

<link href="css/wyse-audiobox.css" rel="stylesheet">

<div class="col-md-8">
  <h3>Server #<?php echo wyse_h($id); ?></h3>
  <p class="wyse-muted"><a href="audiobox.php">&larr; Back to AudioBox</a></p>

  <div class="btn-group btn-group-lg mb-3" role="group">
    <button class="btn btn-secondary btn-info" type="button">
      <?php
      include('status.php');
      echo $status;
      ?>
    </button>
    <?php if (!isset($_GET['new'])) { ?>
      <button class="btn btn-secondary btn-success" type="button" onclick="location.href='action.php?type=start&id=<?php echo wyse_h($id); ?>';">Start</button>
      <button class="btn btn-secondary btn-danger" type="button" onclick="location.href='action.php?type=stop&id=<?php echo wyse_h($id); ?>';">Stop</button>
    <?php } ?>
  </div>

  <form role="form" action="modify_args.php" method="post">
    <input type="hidden" name="nb" value="<?php echo wyse_h($id); ?>">

    <div class="form-group">
      <label for="type">Type</label>
      <select class="form-control" id="type" name="type">
        <option <?php echo $type === 'receptor' ? 'selected' : ''; ?>>receptor</option>
        <option <?php echo $type === 'emitter' ? 'selected' : ''; ?>>emitter</option>
      </select>
    </div>

    <div class="form-group">
      <label for="i">Sender IP</label>
      <input class="form-control" name="i" id="i" type="text"
             value="<?php echo wyse_h(isset($argsParsed['i']) ? $argsParsed['i'] : $defaults['VBAN_SENDER_IP']); ?>">
      <small class="form-text text-muted">For a receptor, this is the VBAN sender address (VoiceMeeter PC), not 0.0.0.0.</small>
    </div>

    <div class="form-group">
      <label for="s">Stream name</label>
      <input class="form-control" name="s" id="s" type="text"
             placeholder="Use AudioBox Scan/Connect to detect from VBAN packets"
             value="<?php echo wyse_h(isset($argsParsed['s']) ? $argsParsed['s'] : ''); ?>">
      <small class="form-text text-muted">Must match VoiceMeeter exactly. Prefer AudioBox Connect, which verifies against incoming packets.</small>
    </div>

    <details class="wyse-card">
      <summary><strong>Advanced settings</strong></summary>

      <div class="form-group mt-3">
        <label for="p">UDP port</label>
        <input class="form-control" name="p" id="p" type="text"
               value="<?php echo wyse_h(isset($argsParsed['p']) ? $argsParsed['p'] : $defaultPort); ?>">
      </div>

      <div class="form-group">
        <label for="b">Audio backend</label>
        <select class="form-control" id="b" name="b">
          <?php
          $backend = isset($argsParsed['b']) ? $argsParsed['b'] : ($defaults['VBAN_BACKEND'] !== '' ? $defaults['VBAN_BACKEND'] : 'pulseaudio');
          foreach (array('pulseaudio', 'alsa', 'jack', 'pipe', 'file') as $option) {
              $selected = $backend === $option ? 'selected' : '';
              echo '<option ' . $selected . '>' . wyse_h($option) . '</option>';
          }
          ?>
        </select>
        <small class="form-text text-muted">Use pulseaudio on the Wyse so NDI and VBAN can run together.</small>
      </div>

      <?php if ($type !== 'emitter') { ?>
        <div class="form-group">
          <label for="q">Network quality</label>
          <select class="form-control" id="q" name="q">
            <?php
            $quality = isset($argsParsed['q']) ? $argsParsed['q'] : '1';
            foreach (array('0', '1', '2', '3', '4') as $option) {
                $selected = $quality === $option ? 'selected' : '';
                echo '<option ' . $selected . '>' . wyse_h($option) . '</option>';
            }
            ?>
          </select>
        </div>
      <?php } else { ?>
        <div class="form-group">
          <label for="r">Sample rate</label>
          <input class="form-control" name="r" id="r" type="text" value="<?php echo wyse_h(isset($argsParsed['r']) ? $argsParsed['r'] : '44100'); ?>">
        </div>
        <div class="form-group">
          <label for="n">Channels</label>
          <input class="form-control" name="n" id="n" type="text" value="<?php echo wyse_h(isset($argsParsed['n']) ? $argsParsed['n'] : '2'); ?>">
        </div>
        <div class="form-group">
          <label for="f">Sample format</label>
          <input class="form-control" name="f" id="f" type="text" value="<?php echo wyse_h(isset($argsParsed['f']) ? $argsParsed['f'] : '16I'); ?>">
        </div>
      <?php } ?>

      <div class="form-group">
        <label for="d">Audio device / Pulse stream label</label>
        <input class="form-control" name="d" id="d" type="text"
               value="<?php echo wyse_h(isset($argsParsed['d']) ? $argsParsed['d'] : ($defaults['VBAN_PULSE_LABEL'] !== '' ? $defaults['VBAN_PULSE_LABEL'] : 'VBAN AudioBox')); ?>">
        <small class="form-text text-muted">With pulseaudio this is a stream name, not the hardware output device.</small>
      </div>

      <div class="form-group">
        <label for="c">Channel map (optional)</label>
        <input class="form-control" name="c" id="c" type="text" value="<?php echo wyse_h(isset($argsParsed['c']) ? $argsParsed['c'] : ''); ?>">
      </div>

      <div class="form-group">
        <label for="l">Log level</label>
        <select class="form-control" id="l" name="l">
          <?php
          $level = isset($argsParsed['l']) ? $argsParsed['l'] : '1';
          foreach (array('0', '1', '2', '3', '4') as $option) {
              $selected = $level === $option ? 'selected' : '';
              echo '<option ' . $selected . '>' . wyse_h($option) . '</option>';
          }
          ?>
        </select>
      </div>
    </details>

    <button type="submit" class="btn btn-primary">Save</button>
    <?php if (!isset($_GET['new'])) { ?>
      <button type="button" class="btn btn-danger" onclick="location.href='action.php?type=remove&id=<?php echo wyse_h($id); ?>';">Remove</button>
    <?php } ?>

    <div class="form-group mt-4">
      <label for="log">Log</label>
      <iframe id="log" src="log.php?id=<?php echo wyse_h($id); ?>" style="width:100%;height:250px;border:1px solid rgba(0,0,0,.15);border-radius:.25rem;"></iframe>
    </div>
  </form>
</div>

<?php include 'bottom.php'; ?>
