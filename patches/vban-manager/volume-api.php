<?php
include 'config.php';
include 'wyse-common.php';

header('Content-Type: application/json');

$defaults = wyse_load_defaults();
$slot = isset($_REQUEST['id']) ? trim($_REQUEST['id']) : $defaults['AUDIOBOX_SLOT'];
$action = isset($_REQUEST['action']) ? trim($_REQUEST['action']) : '';
$percent = isset($_REQUEST['percent']) ? (int)$_REQUEST['percent'] : -1;

if ($percent < 0 || $percent > 150) {
    echo json_encode(array('ok' => false, 'error' => 'Volume must be between 0 and 150.'));
    exit;
}

$current = wyse_read_server_args($slot);
$label = wyse_pulse_label($defaults, $current);
$levels = wyse_audio_levels($label);

if ($action === 'set_sink') {
    wyse_set_sink_volume($percent);
    echo json_encode(array('ok' => true, 'target' => 'sink', 'percent' => $percent));
    exit;
}

if ($action === 'set_stream') {
    $index = isset($levels['stream']['index']) ? (int)$levels['stream']['index'] : 0;
    if ($index <= 0) {
        echo json_encode(array('ok' => false, 'error' => 'VBAN stream is not playing in PulseAudio yet.'));
        exit;
    }
    wyse_set_stream_volume($index, $percent);
    echo json_encode(array('ok' => true, 'target' => 'stream', 'percent' => $percent, 'index' => $index));
    exit;
}

echo json_encode(array('ok' => false, 'error' => 'Unknown action.'));
