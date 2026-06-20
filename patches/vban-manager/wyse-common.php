<?php

function wyse_load_defaults()
{
    $defaults = array(
        'VBAN_UDP_PORT' => '6980',
        'VBAN_BACKEND' => 'pulseaudio',
        'VBAN_PULSE_LABEL' => 'VBAN AudioBox',
        'VBAN_STREAM_NAME' => 'Stream1',
        'VBAN_SENDER_IP' => '',
        'VBAN_ALSA_DEVICE' => '',
        'VBAN_SCAN_SECONDS' => '5',
        'AUDIOBOX_SLOT' => '1',
    );

    $file = '/etc/default/wyse-vban';
    if (!is_readable($file)) {
        return $defaults;
    }

    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (preg_match('/^([A-Z0-9_]+)=(.*)$/', $line, $matches)) {
            $value = trim($matches[2]);
            if ((substr($value, 0, 1) === '"' && substr($value, -1) === '"') ||
                (substr($value, 0, 1) === "'" && substr($value, -1) === "'")) {
                $value = substr($value, 1, -1);
            }
            $defaults[$matches[1]] = $value;
        }
    }

    return $defaults;
}

function wyse_primary_ip()
{
    $ip = trim(shell_exec("ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if (\$i==\"src\") {print \$(i+1); exit}}'") ?? '');
    if ($ip !== '') {
        return $ip;
    }
    $ip = trim(shell_exec("hostname -I 2>/dev/null | awk '{print \$1}'") ?? '');
    return $ip;
}

function wyse_vban_sh($command)
{
    global $script, $script_sh;
    chdir($script);
    return shell_exec('./vban.sh ' . $command . ' 2>&1');
}

function wyse_server_status($id)
{
    global $script, $script_sh;
    chdir($script);
    $status = shell_exec('./vban.sh is-active ' . escapeshellarg($id) . ' 2>&1');
    if (strpos($status, 'active') !== false && strpos($status, 'inactive') === false) {
        return 'active';
    }
    if (strpos($status, 'inactive') !== false) {
        return 'stopped';
    }
    return 'unknown';
}

function wyse_read_server_args($id)
{
    global $args;
    $file = $args . $id . '.txt';
    if (!is_readable($file)) {
        return array();
    }

    $line = trim(file_get_contents($file));
    if ($line === '') {
        return array();
    }

    $parsed = array('raw' => $line);
    if (preg_match('/^(\S+)/', $line, $typeMatch)) {
        $parsed['type'] = $typeMatch[1];
    }

    if (preg_match_all('/-([a-z]) ([^ ]+)/', $line . ' ', $matches)) {
        for ($i = 0; $i < count($matches[1]); $i++) {
            $parsed[$matches[1][$i]] = $matches[2][$i];
        }
    }

    return $parsed;
}

function wyse_list_servers()
{
    global $script, $args_sub;
    $servers = array();
    foreach (glob($script . 'args-*.txt') as $file) {
        $id = substr(basename($file), $args_sub, -4);
        $servers[] = array(
            'id' => $id,
            'status' => wyse_server_status($id),
            'args' => wyse_read_server_args($id),
        );
    }
    return $servers;
}

function wyse_stop_all_streams()
{
    foreach (wyse_list_servers() as $server) {
        if ($server['status'] === 'active') {
            wyse_vban_sh('stop ' . escapeshellarg($server['id']));
        }
    }
}

function wyse_quote_arg($value)
{
    if (preg_match('/[\s"\\\\]/', $value)) {
        return '"' . str_replace('"', '\\"', $value) . '"';
    }
    return $value;
}

function wyse_build_receptor_line($sender, $stream, $port, $defaults)
{
    $backend = $defaults['VBAN_BACKEND'] !== '' ? $defaults['VBAN_BACKEND'] : 'pulseaudio';
    $parts = array(
        'receptor',
        '-i', wyse_quote_arg($sender),
        '-p', wyse_quote_arg((string)$port),
        '-s', wyse_quote_arg($stream),
        '-b', wyse_quote_arg($backend),
    );

    if ($backend === 'pulseaudio') {
        $label = $defaults['VBAN_PULSE_LABEL'] !== '' ? $defaults['VBAN_PULSE_LABEL'] : 'VBAN AudioBox';
        $parts[] = '-d';
        $parts[] = wyse_quote_arg($label);
    } elseif ($backend === 'alsa' && $defaults['VBAN_ALSA_DEVICE'] !== '') {
        $parts[] = '-d';
        $parts[] = wyse_quote_arg($defaults['VBAN_ALSA_DEVICE']);
    }

    $parts[] = '-q';
    $parts[] = '1';
    return implode(' ', $parts);
}

function wyse_connect_stream($id, $sender, $stream, $port, $defaults)
{
    global $args;

    $sender = trim($sender);
    $stream = trim($stream);
    $port = trim((string)$port);

    if ($sender === '' || $stream === '') {
        return 'Sender IP and stream name are required.';
    }
    if ($port === '') {
        $port = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';
    }

    wyse_vban_sh('stop ' . escapeshellarg($id));
    $line = wyse_build_receptor_line($sender, $stream, $port, $defaults);
    file_put_contents($args . $id . '.txt', $line . "\n");
    wyse_vban_sh('start ' . escapeshellarg($id));

    return null;
}

function wyse_h($value)
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}
