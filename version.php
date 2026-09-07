v1.26.5
-
<?php
$str= file_get_contents('https://raw.githubusercontent.com/stuinx/deGWD/fix/version.php');
$array=explode('-', $str);
echo $array[0];
?>
