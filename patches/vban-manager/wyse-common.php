<?php

function wyse_config_path()
{
    return '/etc/default/wyse-vban';
}

function wyse_config_schema()
{
    return array(
        'VBAN_SENDER_IP' => '',
        'VBAN_UDP_PORT' => '6980',
        'VBAN_STREAM_NAME' => 'Stream1',
        'VBAN_SCAN_SECONDS' => '5',
        'VBAN_NETWORK_QUALITY' => '1',
        'VBAN_BACKEND' => 'pulseaudio',
        'VBAN_PULSE_LABEL' => 'VBAN AudioBox',
        'VBAN_PULSE_SINK' => '',
        'VBAN_ALSA_DEVICE' => '',
        'VBAN_STOP_PIPEWIRE_FOR_ALSA' => '1',
        'AUDIOBOX_SLOT' => '1',
        'VBAN_MANAGER_DIR' => '/opt/vban-manager',
        'VBAN_MANAGER_PORT' => '8088',
        'VBAN_MANAGER_BIND' => '0.0.0.0',
    );
}

function wyse_load_defaults()
{
    $config = wyse_config_schema();
    $file = wyse_config_path();
    if (!is_readable($file)) {
        return $config;
    }

    foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (preg_match('/^([A-Z0-9_]+)=(.*)$/', $line, $matches)) {
            if (!array_key_exists($matches[1], $config)) {
                continue;
            }
            $value = trim($matches[2]);
            if ((substr($value, 0, 1) === '"' && substr($value, -1) === '"') ||
                (substr($value, 0, 1) === "'" && substr($value, -1) === "'")) {
                $value = substr($value, 1, -1);
            }
            $config[$matches[1]] = $value;
        }
    }

    return $config;
}

function wyse_config_writable()
{
    $file = wyse_config_path();
    return is_writable($file) || (!file_exists($file) && is_writable(dirname($file)));
}

function wyse_save_defaults($values)
{
    $lines = array();
    foreach (wyse_config_schema() as $key => $default) {
        $value = isset($values[$key]) ? trim((string)$values[$key]) : $default;
        if (preg_match('/[\s"#]/', $value)) {
            $value = str_replace('"', '', $value);
            $lines[] = $key . '="' . $value . '"';
        } else {
            $lines[] = $key . '=' . $value;
        }
    }

    $payload = implode("\n", $lines) . "\n";
    $cmd = 'printf %s ' . escapeshellarg($payload) . ' | /usr/local/bin/wyse-vban-save-config 2>&1';
    $output = trim(shell_exec($cmd) ?? '');
    if ($output === '' || stripos($output, 'Saved ') !== 0) {
        return $output !== '' ? $output : 'Could not save settings.';
    }
    return null;
}

function wyse_list_audio_devices()
{
    $json = trim(shell_exec('/usr/local/bin/wyse-vban-audio-devices 2>&1') ?? '');
    $data = json_decode($json, true);
    if (!is_array($data)) {
        return array(
            'ok' => false,
            'error' => 'Could not list audio devices.',
            'pipewire_running' => false,
            'pulse_sinks' => array(),
            'alsa_cards' => array(),
        );
    }
    return $data;
}

function wyse_prepare_audio($defaults)
{
    $backend = isset($defaults['VBAN_BACKEND']) ? $defaults['VBAN_BACKEND'] : 'pulseaudio';

    if ($backend === 'alsa') {
        if (($defaults['VBAN_STOP_PIPEWIRE_FOR_ALSA'] ?? '1') === '1') {
            shell_exec('/usr/local/bin/vban-box-stop-pipewire 2>/dev/null');
            usleep(500000);
        }
        return;
    }

    shell_exec('/usr/local/bin/vban-box-start-pipewire 2>/dev/null');
    usleep(300000);

    $sink = trim($defaults['VBAN_PULSE_SINK'] ?? '');
    if ($sink !== '') {
        shell_exec('pactl set-default-sink ' . escapeshellarg($sink) . ' 2>/dev/null');
    }
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
    global $script;
    chdir($script);
    return shell_exec('./vban.sh ' . $command . ' 2>&1');
}

function wyse_server_status($id)
{
    global $script;
    chdir($script);
    $status = trim(shell_exec('./vban.sh is-active ' . escapeshellarg($id) . ' 2>&1') ?? '');

    if ($status === 'active') {
        return 'active';
    }
    if ($status === 'activating') {
        return 'activating';
    }
    if ($status === 'failed' || $status === 'auto-restart') {
        return 'failed';
    }
    if ($status === 'inactive') {
        return 'stopped';
    }
    return 'unknown';
}

function wyse_parse_args_line($line)
{
    $line = trim($line);
    if ($line === '') {
        return array();
    }

    $cmd = 'printf %s ' . escapeshellarg($line) . ' | /usr/local/bin/wyse-vban-parse-args 2>/dev/null';
    $json = trim(shell_exec($cmd) ?? '');
    $parsed = json_decode($json, true);
    if (!is_array($parsed)) {
        return array('raw' => $line);
    }
    return $parsed;
}

function wyse_read_server_args($id)
{
    global $args;
    $file = $args . $id . '.txt';
    if (!is_readable($file)) {
        return array();
    }
    return wyse_parse_args_line(file_get_contents($file));
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
        $state = wyse_server_status($server['id']);
        if ($state === 'active' || $state === 'activating') {
            wyse_vban_sh('stop ' . escapeshellarg($server['id']));
        }
    }
}

function wyse_service_journal($id, $lines = 15)
{
    $unit = 'vban@' . $id . '.service';
    return trim(shell_exec(
        'journalctl --user -u ' . escapeshellarg($unit) . ' -n ' . (int)$lines . ' --no-pager 2>&1'
    ) ?? '');
}

function wyse_scan_streams($port, $seconds, $sender_filter = '')
{
    $cmd = '/usr/local/bin/wyse-vban-scan '
        . escapeshellarg((string)$port) . ' '
        . escapeshellarg((string)$seconds);
    if ($sender_filter !== '') {
        $cmd .= ' ' . escapeshellarg($sender_filter);
    }

    $data = json_decode(trim(shell_exec($cmd . ' 2>&1') ?? ''), true);
    if (!is_array($data)) {
        return array('streams' => array(), 'error' => 'Scan failed');
    }
    return $data;
}

function wyse_wait_service($id, $timeout = 4.0)
{
    $deadline = microtime(true) + $timeout;
    while (microtime(true) < $deadline) {
        $state = wyse_server_status($id);
        if ($state === 'active') {
            return 'active';
        }
        if ($state === 'failed') {
            return 'failed';
        }
        usleep(250000);
    }
    return wyse_server_status($id);
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
    $parts[] = isset($defaults['VBAN_NETWORK_QUALITY']) && $defaults['VBAN_NETWORK_QUALITY'] !== ''
        ? wyse_quote_arg($defaults['VBAN_NETWORK_QUALITY'])
        : '1';
    return implode(' ', $parts);
}

function wyse_connect_stream($id, $sender, $stream, $port, $defaults)
{
    global $args;

    $sender = trim($sender);
    $stream = trim($stream);
    $port = trim((string)$port);

    if ($port === '') {
        $port = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';
    }

    wyse_vban_sh('stop ' . escapeshellarg($id));
    usleep(300000);

    if ($stream === '') {
        $seconds = $defaults['VBAN_SCAN_SECONDS'] !== '' ? (float)$defaults['VBAN_SCAN_SECONDS'] : 5.0;
        $scan = wyse_scan_streams($port, $seconds, $sender);
        if (!empty($scan['error']) && empty($scan['streams'])) {
            return 'Could not scan for VBAN streams: ' . $scan['error'];
        }

        $streams = $scan['streams'] ?? array();
        if (empty($streams)) {
            return 'No VBAN stream heard on port ' . $port . '. Start VoiceMeeter VBAN output to this device, then use Scan or enter the stream name manually.';
        }

        $chosen = $streams[0];
        if ($sender !== '') {
            foreach ($streams as $item) {
                if ($item['sender'] === $sender) {
                    $chosen = $item;
                    break;
                }
            }
        } else {
            $sender = $chosen['sender'];
        }
        $stream = $chosen['stream'];
    }

    if ($sender === '') {
        return 'Sender IP is required when the stream name is entered manually.';
    }

    $line = wyse_build_receptor_line($sender, $stream, $port, $defaults);
    file_put_contents($args . $id . '.txt', $line . "\n");
    wyse_prepare_audio($defaults);
    wyse_vban_sh('start ' . escapeshellarg($id));

    $final = wyse_wait_service($id);
    if ($final !== 'active') {
        $log = wyse_service_journal($id, 8);
        $hint = 'Stream name must match VoiceMeeter exactly (case-sensitive).';
        if ($log !== '') {
            return 'VBAN receptor exited (' . $final . '). ' . $hint . ' Log: ' . preg_replace('/\s+/', ' ', $log);
        }
        return 'VBAN receptor did not stay running (' . $final . '). ' . $hint;
    }

    return null;
}

function wyse_connect_result($id, $sender, $stream, $port, $defaults)
{
    $error = wyse_connect_stream($id, $sender, $stream, $port, $defaults);
    $argsParsed = wyse_read_server_args($id);
    $state = wyse_server_status($id);

    return array(
        'ok' => $error === null,
        'error' => $error,
        'state' => $state,
        'sender' => isset($argsParsed['i']) ? $argsParsed['i'] : $sender,
        'stream' => isset($argsParsed['s']) ? $argsParsed['s'] : $stream,
        'port' => isset($argsParsed['p']) ? $argsParsed['p'] : $port,
        'journal' => ($state === 'failed') ? wyse_service_journal($id, 10) : '',
    );
}

function wyse_h($value)
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}
