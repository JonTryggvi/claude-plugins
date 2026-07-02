<?php
// Toggle Breakdance render-performance-debug. Usage: wp eval-file bd_debug.php on|off
$val = (($args[0] ?? '') === 'on');
if (function_exists('Breakdance\\Data\\set_global_option')) {
  \Breakdance\Data\set_global_option('enable_render_performance_debug', $val);
} else {
  update_option('breakdance_enable_render_performance_debug', $val);
}
$now = \Breakdance\Data\get_global_option('enable_render_performance_debug');
echo 'enable_render_performance_debug = ' . var_export($now, true) . PHP_EOL;
