<?php
include 'config.php';
if (!function_exists('wyse_load_defaults')) {
    include_once 'wyse-common.php';
}

$page = isset($page) ? $page : '';
$wyseDefaults = wyse_load_defaults();
?>
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>VBAN AudioBox</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <link href="css/style.css" rel="stylesheet">
    <link href="css/wyse-audiobox.css" rel="stylesheet">
  </head>
  <body class="wyse-app">
    <div class="wyse-shell">
      <aside class="wyse-sidebar" id="wyse-sidebar">
        <div class="wyse-brand">
          <span class="wyse-brand-mark">VBAN</span>
          <span class="wyse-brand-text">AudioBox</span>
        </div>
        <nav class="wyse-nav">
          <a class="wyse-nav-link<?php echo $page === 'audiobox' ? ' active' : ''; ?>" id="page-audiobox" href="audiobox.php">Dashboard</a>
          <a class="wyse-nav-link<?php echo $page === 'settings' ? ' active' : ''; ?>" id="page-settings" href="settings.php">Settings</a>
          <div class="wyse-nav-section">Advanced</div>
          <?php
          $serverFiles = glob(wyse_script_dir() . '/args-*.txt');
          $nextId = 1;
          if ($serverFiles) {
              foreach ($serverFiles as $file) {
                  $serverId = wyse_args_id_from_file($file);
                  $nextId = max($nextId, (int)$serverId + 1);
                  $active = ($page === 'server' && isset($_GET['id']) && (string)$_GET['id'] === (string)$serverId) ? ' active' : '';
                  ?>
          <a class="wyse-nav-link wyse-nav-link-sub<?php echo $active; ?>" href="server.php?id=<?php echo wyse_h($serverId); ?>"><?php echo wyse_h(wyse_server_nav_label($serverId)); ?></a>
                  <?php
              }
          }
          ?>
          <a class="wyse-nav-link wyse-nav-link-sub" href="server.php?id=<?php echo wyse_h((string)$nextId); ?>&new=true">+ New server</a>
          <?php
          $plugins = glob($plugins_folder . '*', GLOB_ONLYDIR);
          foreach ($plugins as $plugin) {
              $name = substr($plugin, $plugins_sub);
              ?>
          <a class="wyse-nav-link wyse-nav-link-sub" id="page-plugins-<?php echo wyse_h($name); ?>" href="plugin.php?name=<?php echo wyse_h($name); ?>"><?php echo wyse_h($name); ?></a>
              <?php
          }
          ?>
        </nav>
        <div class="wyse-sidebar-footer">
          <a class="wyse-nav-link wyse-nav-link-muted" href="https://github.com/VBAN-manager/VBAN-manager" target="_blank" rel="noopener">Project</a>
        </div>
      </aside>

      <div class="wyse-main">
        <header class="wyse-topbar">
          <button class="wyse-nav-toggle btn btn-light" type="button" id="wyse-nav-toggle" aria-label="Toggle navigation">Menu</button>
          <div class="wyse-topbar-title">VBAN AudioBox</div>
        </header>

        <div class="wyse-content-wrap">
          <?php if (isset($_GET['message'])) { ?>
          <div class="alert alert-success alert-dismissible wyse-flash">
            <a href="#" class="close" data-dismiss="alert" aria-label="close">&times;</a>
            <strong><?php echo wyse_h(urldecode($_GET['message'])); ?></strong>
          </div>
          <?php } ?>

          <div class="row wyse-page-row">
