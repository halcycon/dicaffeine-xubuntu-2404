<?php
include 'config.php';
include 'wyse-common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: settings.php');
    exit;
}

if (!wyse_config_writable()) {
    header('Location: settings.php?error=' . urlencode('Settings file is not writable by the web UI user.'));
    exit;
}

$values = array();
foreach (wyse_config_schema() as $key => $default) {
    if ($key === 'VBAN_STOP_PIPEWIRE_FOR_ALSA') {
        $values[$key] = isset($_POST[$key]) ? '1' : '0';
        continue;
    }
    if (isset($_POST[$key])) {
        $values[$key] = trim((string)$_POST[$key]);
    } else {
        $values[$key] = $default;
    }
}

$error = wyse_save_defaults($values);
if ($error !== null) {
    header('Location: settings.php?error=' . urlencode($error));
    exit;
}

header('Location: settings.php?message=' . urlencode('Settings saved to ' . wyse_config_path()));
exit;
