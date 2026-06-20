<?php
include 'config.php';
include 'wyse-common.php';

$defaults = wyse_load_defaults();
$id = isset($_REQUEST['id']) ? trim($_REQUEST['id']) : $defaults['AUDIOBOX_SLOT'];
$sender = isset($_REQUEST['sender']) ? trim($_REQUEST['sender']) : '';
$stream = isset($_REQUEST['stream']) ? trim($_REQUEST['stream']) : '';
$port = isset($_REQUEST['port']) ? trim($_REQUEST['port']) : $defaults['VBAN_UDP_PORT'];

$result = wyse_connect_result($id, $sender, $stream, $port, $defaults);

if (isset($_GET['json']) || (isset($_SERVER['HTTP_ACCEPT']) && strpos($_SERVER['HTTP_ACCEPT'], 'application/json') !== false)) {
    header('Content-Type: application/json');
    echo json_encode($result);
    exit;
}

if ($result['ok']) {
    $message = 'Connected to ' . $result['stream'] . ' from ' . $result['sender'];
} else {
    $message = $result['error'];
}

header('Location: audiobox.php?message=' . urlencode($message));
exit;
