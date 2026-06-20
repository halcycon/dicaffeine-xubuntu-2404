<?php
include 'config.php';
include 'wyse-common.php';

$id = isset($_POST['nb']) ? trim($_POST['nb']) : '';
$type = isset($_POST['type']) ? trim($_POST['type']) : 'receptor';

if ($id === '') {
    header('Location: audiobox.php?message=' . urlencode('Missing server id.'));
    exit;
}

$keys = array('i', 's', 'p', 'b', 'd', 'q', 'c', 'l', 'r', 'n', 'f');
$parts = array($type);
foreach ($keys as $key) {
    if (!isset($_POST[$key])) {
        continue;
    }
    $value = trim((string)$_POST[$key]);
    if ($value === '') {
        continue;
    }
    $parts[] = '-' . $key;
    $parts[] = wyse_quote_arg($value);
}

$line = implode(' ', $parts);
$argsFile = wyse_args_path($id);
if (file_put_contents($argsFile, $line . "\n", LOCK_EX) === false) {
    header('Location: server.php?id=' . urlencode($id) . '&message=' . urlencode('Could not save args file.'));
    exit;
}

header('Location: server.php?id=' . urlencode($id) . '&message=' . urlencode('Settings saved.'));
exit;
