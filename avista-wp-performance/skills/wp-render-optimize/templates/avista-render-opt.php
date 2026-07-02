<?php
/**
 * Plugin Name: Avista Render Optimizations
 * Description: Drops WordPress block-theme global-styles + font-face overhead on a CLASSIC (non-block) theme such as breakdance-zero. Dead weight there: ~30+ ms + a WP_Query on the (empty) wp_global_styles CPT per front-end render. Front-end only; self-guards on wp_is_block_theme().
 * Version:     1.1.0
 * Author:      Avista
 *
 * Drop-in mu-plugin: wp-content/mu-plugins/avista-render-opt.php
 *
 * SAFETY: these removals are ONLY correct on a classic theme. On a real block (FSE) theme
 * the same callbacks generate the site's actual styling — removing them would strip the CSS.
 * The wp_is_block_theme() guard below makes this a no-op on a block theme even if the file is
 * deployed to the wrong site. Still confirm wp_is_block_theme() === false at deploy time.
 */

// Bail entirely on a block theme — belt-and-suspenders so this can never strip a real block
// theme's styling. On a classic theme this is false and the optimizations below apply.
if (function_exists('wp_is_block_theme') && wp_is_block_theme()) {
  return;
}

add_action('init', static function (): void {
  if (is_admin()) {
    return; // leave the editor / admin untouched
  }
  // On a classic theme these callbacks generate block-theme CSS/font-faces that nothing on the
  // site uses, and trigger a WP_Query on the (empty) wp_global_styles CPT on every render.
  remove_action('wp_head', 'wp_print_font_faces', 50);
  remove_action('wp_enqueue_scripts', 'wp_enqueue_global_styles');
  remove_action('wp_footer', 'wp_enqueue_global_styles', 1);
  remove_action('wp_enqueue_scripts', ['WP_Duotone', 'output_global_styles'], 11);
}, 100);

// Belt-and-suspenders: make sure the generated handles aren't left enqueued.
add_action('wp_enqueue_scripts', static function (): void {
  if (is_admin()) {
    return;
  }
  wp_dequeue_style('global-styles');
  wp_dequeue_style('global-styles-css-custom-properties');
}, 100);
