<?php
include 'config.php';
include 'wyse-common.php';

$defaults = wyse_load_defaults();
$id = isset($_REQUEST['id']) ? trim($_REQUEST['id']) : $defaults['AUDIOBOX_SLOT'];
$sender = isset($_REQUEST['sender']) ? trim($_REQUEST['sender']) : '';
$stream = isset($_REQUEST['stream']) ? trim($_REQUEST['stream']) : '';
$port = isset($_REQUEST['port']) ? trim($_REQUEST['port']) : $defaults['VBAN_UDP_PORT'];

$error = wyse_connect_stream($id, $sender, $stream, $port, $defaults);
$message = $error ? $error : 'Connected to ' . $stream . ' from ' . $sender;

if (isset($_GET['json'])) {
    header('Content-Type: application/json');
    echo json_encode(array(
        'ok' => $error === null,
        'message' => $message,
    ));
    exit;
}

header('Location: audiobox.php?message=' . urlencode($message));
exit;
