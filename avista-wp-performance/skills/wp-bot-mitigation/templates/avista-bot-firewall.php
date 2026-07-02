<?php
/**
 * Plugin Name: Avista Bot Firewall
 * Description: Early 403 for zero-value crawlers/scrapers, before the expensive Breakdance render. Keeps Google/Bing, the WP loopback, cron, admin and REST untouched.
 * Version:     1.0.0
 * Author:      Avista
 *
 * Drop-in mu-plugin: place at wp-content/mu-plugins/avista-bot-firewall.php
 * (mu-plugins load before regular plugins/theme, so a match exits before the ~4-45s render).
 *
 * Evidence: 8-day access-log audit (Jun 25 - Jul 2 2026). Blockable bots consumed
 * ~41 h of server render time over 8 days (~31% of all processing). See production-notes/findings.md.
 */

// Bail on anything that isn't a public HTTP hit.
if (php_sapi_name() === 'cli' || (defined('WP_CLI') && WP_CLI)) {
  return;
}

final class Avista_Bot_Firewall {

  /**
   * User-agent substrings to hard-block (matched case-insensitively).
   * Only zero SEO / zero business-value crawlers. Googlebot & bingbot are absent by design.
   */
  private const BLOCK_UA = [
    'dataforseobot',
    'meta-externalagent',
    'amazonbot',
    'bytespider',
    'claudebot',
    'anthropic-ai',
    'gptbot',
    'chatgpt-user',
    'ccbot',
    'perplexitybot',
    'petalbot',
    'dotbot',
    'mj12bot',
    'semrushbot',
    'ahrefsbot',
    'imagesift',
    'timpibot',
    'java-http-client',
    'python-requests',
    'go-http-client',
    'scrapy',
    'libwww-perl',
    'microsoft office',
  ];

  /**
   * Exact client IPs to block (spoofed browser UAs the list above cannot catch).
   * Confirmed heavy offenders from the 8-day audit.
   */
  private const BLOCK_IP = [
    '152.163.2.216',   // broken crawler: malformed /https%3A/... URLs, ~45s/req, 16,260s in one day
    '34.101.40.191',   // zh-CN Android bot, ~33s/req
    // '89.160.223.119', // REVIEW FIRST: 9,882 req/8d on a browser UA (52,001s). Confirm not a legit partner/monitor before enabling.
  ];

  /** Paths never touched by the firewall (admin, cron, login, REST, ajax). */
  private const SKIP_PATH = [
    '/wp-admin',
    'wp-cron.php',
    'wp-login.php',
    '/wp-json/',
    'admin-ajax.php',
  ];

  public static function guard(): void {
    $uri = $_SERVER['REQUEST_URI'] ?? '';
    foreach (self::SKIP_PATH as $skip) {
      if (stripos($uri, $skip) !== false) {
        return;
      }
    }

    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    if ($ip !== '' && in_array($ip, self::BLOCK_IP, true)) {
      self::deny();
    }

    $ua = strtolower($_SERVER['HTTP_USER_AGENT'] ?? '');

    // Empty UA on a public page hit: block. (WP loopback uses "WordPress/...", uptime
    // monitor and preloader send real UAs, so this only catches anonymous scrapers.)
    if ($ua === '') {
      self::deny();
    }

    foreach (self::BLOCK_UA as $needle) {
      if (str_contains($ua, $needle)) {
        self::deny();
      }
    }
  }

  private static function deny(): never {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    header('Cache-Control: no-store');
    header('Retry-After: 86400');
    echo '403 Forbidden';
    exit;
  }
}

Avista_Bot_Firewall::guard();
