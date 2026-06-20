<?php
$manager_dir = '/opt/vban-manager';
$config_file = '/etc/default/wyse-vban';

if (is_readable($config_file)) {
    foreach (file($config_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (preg_match('/^VBAN_MANAGER_DIR=(.*)$/', $line, $matches)) {
            $value = trim($matches[1]);
            if ((substr($value, 0, 1) === '"' && substr($value, -1) === '"') ||
                (substr($value, 0, 1) === "'" && substr($value, -1) === "'")) {
                $value = substr($value, 1, -1);
            }
            if ($value !== '') {
                $manager_dir = rtrim($value, '/');
            }
        }
    }
}

$script = $manager_dir . '/script/';
$script_sh = $script . 'vban.sh';
$args = $script . 'args-';
$args_sub = strlen($args);
$plugins_folder = $manager_dir . '/plugins/';
$plugins_sub = strlen($plugins_folder);
