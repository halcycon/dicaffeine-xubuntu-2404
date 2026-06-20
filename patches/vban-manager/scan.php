<?php
include 'config.php';
include 'wyse-common.php';

header('Content-Type: application/json');

$defaults = wyse_load_defaults();
$port = isset($_GET['port']) ? trim($_GET['port']) : $defaults['VBAN_UDP_PORT'];
$seconds = isset($_GET['seconds']) ? trim($_GET['seconds']) : $defaults['VBAN_SCAN_SECONDS'];
$stopFirst = !isset($_GET['stop']) || $_GET['stop'] !== '0';

if ($port === '') {
    $port = '6980';
}
if ($seconds === '') {
    $seconds = '5';
}

if ($stopFirst) {
    wyse_stop_all_streams();
    usleep(300000);
}

$cmd = '/usr/local/bin/wyse-vban-scan ' . escapeshellarg($port) . ' ' . escapeshellarg($seconds);
$output = shell_exec($cmd . ' 2>&1');
$data = json_decode(trim((string)$output), true);

if (!is_array($data)) {
    echo json_encode(array(
        'ok' => false,
        'port' => (int)$port,
        'duration' => (float)$seconds,
        'streams' => array(),
        'error' => 'Scan failed: ' . trim((string)$output),
    ));
    exit;
}

$data['receiver_ip'] = wyse_primary_ip();
if (!empty($data['streams']) && is_array($data['streams'])) {
    wyse_save_scan_cache($port, $data['streams']);
}
echo json_encode($data);
