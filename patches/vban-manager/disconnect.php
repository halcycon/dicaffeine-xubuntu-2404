<?php
include 'config.php';
include 'wyse-common.php';

$defaults = wyse_load_defaults();
$id = isset($_REQUEST['id']) ? trim($_REQUEST['id']) : '';

if ($id !== '') {
    wyse_vban_sh('stop ' . escapeshellarg($id));
    $message = 'Stopped stream #' . $id;
} else {
    wyse_stop_all_streams();
    $message = 'Stopped all VBAN streams';
}

if (isset($_GET['json'])) {
    header('Content-Type: application/json');
    echo json_encode(array('ok' => true, 'message' => $message));
    exit;
}

header('Location: audiobox.php?message=' . urlencode($message));
exit;
