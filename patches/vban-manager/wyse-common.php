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
            shell_exec(wyse_user_env_prefix() . ' /usr/local/bin/vban-box-stop-pipewire 2>/dev/null');
            usleep(500000);
        }
        return;
    }

    shell_exec(wyse_user_env_prefix() . ' /usr/local/bin/vban-box-start-pipewire 2>/dev/null');
    usleep(500000);

    $sink = trim($defaults['VBAN_PULSE_SINK'] ?? '');
    if ($sink !== '') {
        shell_exec(wyse_user_env_prefix() . ' pactl set-default-sink ' . escapeshellarg($sink) . ' 2>/dev/null');
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

function wyse_manager_dir()
{
    static $dir = null;
    if ($dir !== null) {
        return $dir;
    }

    $dir = '/opt/vban-manager';
    $defaults = wyse_load_defaults();
    if (!empty($defaults['VBAN_MANAGER_DIR'])) {
        $dir = rtrim($defaults['VBAN_MANAGER_DIR'], '/');
    }
    return $dir;
}

function wyse_script_dir()
{
    return wyse_manager_dir() . '/script';
}

function wyse_args_path($id)
{
    return wyse_script_dir() . '/args-' . $id . '.txt';
}

function wyse_args_id_from_file($path)
{
    if (preg_match('/^args-(.+)\.txt$/', basename($path), $matches)) {
        return $matches[1];
    }
    return basename($path, '.txt');
}

function wyse_user_env_prefix()
{
    $uid = function_exists('posix_getuid') ? posix_getuid() : 0;
    if ($uid <= 0) {
        $uid = trim(shell_exec('id -u') ?? '0');
    }
    return 'XDG_RUNTIME_DIR=/run/user/' . $uid
        . ' DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/' . $uid . '/bus'
        . ' PULSE_SERVER=unix:/run/user/' . $uid . '/pulse/native'
        . ' PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
}

function wyse_vban_sh($command)
{
    $vbanSh = wyse_script_dir() . '/vban.sh';
    return shell_exec(wyse_user_env_prefix() . ' ' . escapeshellarg($vbanSh) . ' ' . $command . ' 2>&1');
}

function wyse_server_status($id)
{
    $status = trim(shell_exec(wyse_user_env_prefix() . ' ' . escapeshellarg(wyse_script_dir() . '/vban.sh') . ' is-active ' . escapeshellarg($id) . ' 2>&1') ?? '');

    if ($status === 'active') {
        return 'active';
    }
    if ($status === 'activating') {
        $journal = wyse_service_journal($id, 8);
        if (stripos($journal, 'Could not find vban_') !== false ||
            stripos($journal, 'not found in PATH') !== false ||
            stripos($journal, 'Missing args-') !== false ||
            stripos($journal, 'Connection refused') !== false ||
            stripos($journal, 'Failed to connect') !== false ||
            stripos($journal, 'code=exited') !== false ||
            stripos($journal, 'status=127') !== false ||
            stripos($journal, 'status=203') !== false ||
            stripos($journal, 'Start-Limit') !== false ||
            (stripos($journal, 'pulse') !== false && stripos($journal, 'error') !== false)) {
            return 'failed';
        }
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
    $file = wyse_args_path($id);
    if (!is_readable($file)) {
        return array();
    }
    return wyse_parse_args_line(file_get_contents($file));
}

function wyse_list_servers()
{
    $servers = array();
    foreach (glob(wyse_script_dir() . '/args-*.txt') as $file) {
        $id = wyse_args_id_from_file($file);
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
    $journal = trim(shell_exec(
        wyse_user_env_prefix() . ' journalctl --user -u ' . escapeshellarg($unit) . ' -n ' . (int)$lines . ' --no-pager 2>&1'
    ) ?? '');

    $logFile = '/opt/vban-manager/script/vban-' . $id . '.log';
    if (is_readable($logFile)) {
        $tail = trim(shell_exec('tail -n ' . (int)$lines . ' ' . escapeshellarg($logFile) . ' 2>/dev/null') ?? '');
        if ($tail !== '') {
            $journal .= ($journal !== '' ? "\n\n--- vban log ---\n" : '') . $tail;
        }
    }

    return $journal;
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

function wyse_scan_cache_path()
{
    return wyse_script_dir() . '/last-scan.json';
}

function wyse_save_scan_cache($port, $streams)
{
    $payload = array(
        'time' => time(),
        'port' => (int)$port,
        'streams' => is_array($streams) ? $streams : array(),
    );
    file_put_contents(wyse_scan_cache_path(), json_encode($payload), LOCK_EX);
}

function wyse_load_scan_cache($port, $maxAgeSeconds = 120)
{
    $file = wyse_scan_cache_path();
    if (!is_readable($file)) {
        return null;
    }

    $data = json_decode(file_get_contents($file), true);
    if (!is_array($data) || !isset($data['time'], $data['streams']) || !is_array($data['streams'])) {
        return null;
    }
    if ((int)$data['port'] !== (int)$port) {
        return null;
    }
    if (time() - (int)$data['time'] > $maxAgeSeconds) {
        return null;
    }

    return $data['streams'];
}

function wyse_merge_scan_streams()
{
    $merged = array();
    $seen = array();

    foreach (func_get_args() as $streams) {
        if (!is_array($streams)) {
            continue;
        }
        foreach ($streams as $item) {
            if (!is_array($item)) {
                continue;
            }
            $key = ($item['sender'] ?? '') . '|' . ($item['stream'] ?? '') . '|' . ($item['port'] ?? '');
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $merged[] = $item;
        }
    }

    usort($merged, function ($a, $b) {
        return strcmp(
            ($a['sender'] ?? '') . ($a['stream'] ?? ''),
            ($b['sender'] ?? '') . ($b['stream'] ?? '')
        );
    });

    return $merged;
}

function wyse_streams_for_sender($streams, $sender)
{
    if ($sender === '') {
        return $streams;
    }

    $filtered = array();
    foreach ($streams as $item) {
        if (($item['sender'] ?? '') === $sender) {
            $filtered[] = $item;
        }
    }
    return $filtered;
}

function wyse_resolve_stream_name($sender, $requestedStream, $port, $defaults)
{
    $requestedStream = trim($requestedStream);
    $sender = trim($sender);

    if ($port === '') {
        $port = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';
    }

    $scanSeconds = $defaults['VBAN_SCAN_SECONDS'] !== '' ? (float)$defaults['VBAN_SCAN_SECONDS'] : 5.0;
    if ($requestedStream !== '') {
        $scanSeconds = min($scanSeconds, 3.0);
    }

    $cached = wyse_load_scan_cache($port);
    $live = wyse_scan_streams($port, $scanSeconds, $sender);
    if (!empty($live['error']) && empty($live['streams']) && empty($cached)) {
        return array('error' => 'Could not scan for VBAN streams: ' . $live['error']);
    }

    $streams = wyse_merge_scan_streams($cached, $live['streams'] ?? array());
    if ($sender !== '') {
        $streams = wyse_streams_for_sender($streams, $sender);
    }

    if (empty($streams)) {
        if ($requestedStream !== '') {
            return array(
                'error' => 'No VBAN packets heard from '
                    . ($sender !== '' ? $sender : 'any sender')
                    . ' on port ' . $port
                    . '. Cannot verify stream name "'
                    . $requestedStream
                    . '". Start VoiceMeeter output and use Scan first.',
            );
        }
        return array(
            'error' => 'No VBAN stream heard on port ' . $port
                . '. Start VoiceMeeter VBAN output to this device, then use Scan or enter the sender IP and leave stream name blank.',
        );
    }

    if ($sender === '') {
        $sender = $streams[0]['sender'];
    }

    if ($requestedStream !== '') {
        foreach ($streams as $item) {
            if (($item['stream'] ?? '') === $requestedStream) {
                return array(
                    'sender' => $sender,
                    'stream' => $requestedStream,
                    'notice' => null,
                );
            }
        }

        if (count($streams) === 1) {
            $detected = $streams[0]['stream'];
            return array(
                'sender' => $sender,
                'stream' => $detected,
                'notice' => 'Used stream name "' . $detected . '" from VBAN packets instead of "' . $requestedStream . '".',
            );
        }

        $names = array();
        foreach ($streams as $item) {
            $names[] = '"' . ($item['stream'] ?? '') . '"';
        }
        return array(
            'error' => 'Stream name "' . $requestedStream . '" was not seen in VBAN packets from '
                . $sender . '. Detected: ' . implode(', ', $names) . '. Names are case-sensitive.',
        );
    }

    if (count($streams) === 1) {
        return array(
            'sender' => $sender,
            'stream' => $streams[0]['stream'],
            'notice' => null,
        );
    }

    return array(
        'sender' => $sender,
        'stream' => $streams[0]['stream'],
        'notice' => 'Multiple streams heard; connected to "' . $streams[0]['stream'] . '".',
    );
}

function wyse_wait_service($id, $timeout = 8.0)
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
        usleep(300000);
    }
    $state = wyse_server_status($id);
    if ($state === 'activating') {
        return 'failed';
    }
    return $state;
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
    $sender = trim($sender);
    $stream = trim($stream);
    $port = trim((string)$port);

    if ($port === '') {
        $port = $defaults['VBAN_UDP_PORT'] !== '' ? $defaults['VBAN_UDP_PORT'] : '6980';
    }

    wyse_vban_sh('stop ' . escapeshellarg($id));
    usleep(300000);
    shell_exec(wyse_user_env_prefix() . ' systemctl --user reset-failed ' . escapeshellarg('vban@' . $id . '.service') . ' 2>/dev/null');

    $resolved = wyse_resolve_stream_name($sender, $stream, $port, $defaults);
    if (isset($resolved['error'])) {
        return array('error' => $resolved['error'], 'notice' => null);
    }

    $sender = $resolved['sender'];
    $stream = $resolved['stream'];
    $notice = isset($resolved['notice']) ? $resolved['notice'] : null;

    if ($sender === '') {
        return array('error' => 'Sender IP is required when the stream name is entered manually.', 'notice' => null);
    }

    $line = wyse_build_receptor_line($sender, $stream, $port, $defaults);
    $argsFile = wyse_args_path($id);
    if (file_put_contents($argsFile, $line . "\n", LOCK_EX) === false) {
        return array('error' => 'Could not write stream config to ' . $argsFile . '. Check permissions on /opt/vban-manager/script/.', 'notice' => null);
    }
    if (!is_readable($argsFile)) {
        return array('error' => 'Stream config was not saved (' . $argsFile . ' missing after write).', 'notice' => null);
    }

    wyse_prepare_audio($defaults);
    wyse_vban_sh('start ' . escapeshellarg($id));

    $final = wyse_wait_service($id);
    if ($final !== 'active') {
        $log = wyse_service_journal($id, 8);
        if (stripos($log, 'Missing args-') !== false) {
            return array('error' => 'VBAN args file missing at ' . $argsFile . '. Update the kit and try Connect again.', 'notice' => null);
        }
        $hint = 'Stream name must match VoiceMeeter exactly (case-sensitive).';
        if ($log !== '') {
            return array('error' => 'VBAN receptor exited (' . $final . '). ' . $hint . ' Log: ' . preg_replace('/\s+/', ' ', $log), 'notice' => null);
        }
        return array('error' => 'VBAN receptor did not stay running (' . $final . '). ' . $hint, 'notice' => null);
    }

    return array('error' => null, 'notice' => $notice);
}

function wyse_connect_result($id, $sender, $stream, $port, $defaults)
{
    $connect = wyse_connect_stream($id, $sender, $stream, $port, $defaults);
    $error = $connect['error'] ?? 'Connect failed.';
    $notice = $connect['notice'] ?? null;
    $argsParsed = wyse_read_server_args($id);
    $state = wyse_server_status($id);

    return array(
        'ok' => $error === null,
        'error' => $error,
        'notice' => $notice,
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

function wyse_pulse_label($defaults, $args = array())
{
    if (!empty($args['d'])) {
        return $args['d'];
    }
    if (!empty($defaults['VBAN_PULSE_LABEL'])) {
        return $defaults['VBAN_PULSE_LABEL'];
    }
    return 'VBAN AudioBox';
}

function wyse_server_nav_label($id)
{
    $args = wyse_read_server_args($id);
    $state = wyse_server_status($id);
    $prefix = $state === 'active' ? '● ' : '';

    if (!empty($args['i']) && !empty($args['s'])) {
        return $prefix . $args['i'] . ' · ' . $args['s'];
    }
    if (!empty($args['s'])) {
        return $prefix . $args['s'];
    }
    if (!empty($args['i'])) {
        return $prefix . $args['i'];
    }

    return $prefix . 'Server #' . $id;
}

function wyse_audio_levels($pulseLabel = '')
{
    $cmd = '/usr/local/bin/wyse-vban-audio-levels ' . escapeshellarg($pulseLabel !== '' ? $pulseLabel : 'VBAN AudioBox');
    $json = trim(shell_exec(wyse_user_env_prefix() . ' ' . $cmd . ' 2>&1') ?? '');
    $data = json_decode($json, true);
    if (!is_array($data)) {
        return array('ok' => false, 'error' => 'Could not read audio levels.');
    }
    return $data;
}

function wyse_set_sink_volume($percent)
{
    $percent = max(0, min(150, (int)$percent));
    shell_exec(wyse_user_env_prefix() . ' pactl set-sink-volume @DEFAULT_SINK@ ' . (int)$percent . '% 2>/dev/null');
}

function wyse_set_stream_volume($index, $percent)
{
    $index = (int)$index;
    $percent = max(0, min(150, (int)$percent));
    if ($index <= 0) {
        return;
    }
    shell_exec(
        wyse_user_env_prefix()
        . ' pactl set-sink-input-volume '
        . $index
        . ' '
        . (int)$percent
        . '% 2>/dev/null'
    );
}
