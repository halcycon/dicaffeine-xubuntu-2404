<?php
include 'config.php';
include 'wyse-common.php';

header('Content-Type: application/json');
echo json_encode(wyse_list_audio_devices());
