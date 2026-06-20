<?php
include 'config.php';
include 'wyse-common.php';

header('Content-Type: application/json');

$defaults = wyse_load_defaults();
$slot = isset($_GET['id']) ? trim($_GET['id']) : $defaults['AUDIOBOX_SLOT'];
$current = wyse_read_server_args($slot);
$label = wyse_pulse_label($defaults, $current);
$data = wyse_audio_levels($label);
$data['slot'] = $slot;
$data['pulse_label'] = $label;

echo json_encode($data);
