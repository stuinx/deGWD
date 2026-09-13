<?php
require_once('../auth.php');
if (empty($auth)) { http_response_code(403); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); exit; }
$presets = json_decode(file_get_contents(__DIR__ . '/../routing-presets.json'), true);
$selections = json_decode($_POST['selections'] ?? '', true);
if (!is_array($selections) || count($selections) !== count($presets)) {
    http_response_code(400); exit('分流选项不完整');
}
foreach ($presets as $key => $preset) {
    if (!isset($selections[$key]) || !is_int($selections[$key]) || $selections[$key] < 0) {
        http_response_code(400); exit('无效的节点选项');
    }
}
exec('sudo /opt/de_GWD/ui-NodeSM r ' . escapeshellarg(json_encode($selections)) . ' 2>&1', $output, $status);
if ($status !== 0) { http_response_code(500); exit('规则未生效，请检查节点配置和服务日志。'); }
echo '已保存';
