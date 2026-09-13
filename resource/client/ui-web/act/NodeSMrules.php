<?php require_once('../auth.php'); ?>
<?php if (isset($auth) && $auth) {
    if (isset($_POST['json_data'])) {
        $json_data = $_POST['json_data'];
        $reload = (isset($_POST['reload']) && $_POST['reload'] === 'true') ? 'r' : '';
        $cmd = 'sudo /opt/de_GWD/ui-NodeSM set-json ' . escapeshellarg($json_data) . ' ' . escapeshellarg($reload);
        exec($cmd);
        echo json_encode(["status" => "ok"]);
        exit;
    }

    $serviceNames = [
        'nodeSMshowYoutube',
        'nodeSMshowNetflix',
        'nodeSMshowHDH',
        'nodeSMshowTVB',
        'nodeSMshowBahamut',
        'nodeSMshowOpenai',
        'nodeSMshowApple',
        'nodeSMshowSteam',
        'nodeSMshowClaude',
        'nodeSMshowGemini',
        'nodeSMshowGrok',
        'nodeSMshowHuggingface',
        'nodeSMshowOpenrouter',
        'nodeSMshowWiki',
        'nodeSMshowReddit',
        'nodeSMshowTwitter',
        'nodeSMshowTelegram',
        'nodeSMshowBing',
        'nodeSMshowSpotify',
        'nodeSMshowGoogleplay'
    ];

    $args = ['r'];
    foreach ($serviceNames as $name) {
        $val = $_GET[$name] ?? '0';
        $val = is_scalar($val) ? (string) $val : '0';
        $args[] = preg_match('/^[0-9]+$/', $val) ? $val : '0';
    }

    $cmd = 'sudo /opt/de_GWD/ui-NodeSM ' . implode(' ', array_map('escapeshellarg', $args));
    exec($cmd);
}
?>
