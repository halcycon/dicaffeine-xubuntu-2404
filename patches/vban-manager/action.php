<?php
include 'config.php';

$redirect = 'server.php?id=' . urlencode($_GET['id']);
if (isset($_GET['id']) && $_GET['id'] === '1') {
    $redirect = 'audiobox.php';
}

$command = $script_sh." ".$_GET['type']." ".$_GET['id'];
chdir($script);
$return = shell_exec($command);

header("Refresh: 0;url=" . $redirect . "&message=" . urlencode("Action executed!<br/>" . $return));
?>
