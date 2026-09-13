<?php require_once('../auth.php'); ?>
<?php if (isset($auth) && $auth) {?>
<?php
$updateAddr = $_GET['updateAddr'];
$updatePort = $_GET['updatePort'];
$updateCMD = $_GET['updateCMD'];

$conf = json_decode(file_get_contents('/opt/de_GWD/0conf'), true);
$conf['update']['updateAddr'] = $updateAddr;
$conf['update']['updatePort'] = $updatePort;
$conf['update']['updateCMD'] = $updateCMD;
$newJsonString = json_encode($conf, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
file_put_contents('/opt/de_GWD/0conf', $newJsonString);


exec("sudo /opt/de_GWD/ui-updateSave 2>&1", $updateOutput, $updateStatus);
if ($updateStatus !== 0) {
    http_response_code(502);
    echo "更新脚本下载失败";
    exit;
}

if(filter_var($updateAddr, FILTER_VALIDATE_IP)) {
} else {
$updateAddr = gethostbyname($updateAddr);
}

echo "$updateAddr:$updatePort";
?>
<?php }?>
