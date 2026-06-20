<?php
include 'config.php';
include 'wyse-common.php';

header('Content-Type: application/json');

$defaults = wyse_load_defaults();
$id = isset($_GET['id']) ? trim($_GET['id']) : $defaults['AUDIOBOX_SLOT'];
$state = wyse_server_status($id);
$current = wyse_read_server_args($id);

echo json_encode(array(
    'id' => $id,
    'state' => $state,
    'sender' => isset($current['i']) ? $current['i'] : '',
    'stream' => isset($current['s']) ? $current['s'] : '',
    'port' => isset($current['p']) ? $current['p'] : ($defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980'),
    'backend' => isset($current['b']) ? $current['b'] : '',
    'journal' => ($state === 'failed' || $state === 'activating') ? wyse_service_journal($id, 12) : '',
));
