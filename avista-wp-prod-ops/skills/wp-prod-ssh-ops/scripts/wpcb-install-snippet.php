<?php
/**
 * WP Code Box 2 snippet installer template.
 *
 * Inserts a new row into {prefix}wpcb_snippets by cloning a known-good
 * existing row, then overriding only the fields we care about. This avoids
 * hand-authoring the `hook` / `conditions` / `location` / `tagOptions` JSON.
 *
 * Usage:
 *   1. Edit the four placeholders below.
 *   2. Transport this file and the snippet source file to /tmp on the host
 *      via base64 (see SKILL.md, Step C).
 *   3. Run:  wp eval-file /tmp/wpcb-install.php
 *   4. rm both /tmp files.
 *
 * Output:
 *   EXISTS        — row with that title already exists, nothing inserted.
 *   INSERTED:<id> — new row id.
 *   ERR:<msg>     — $wpdb->last_error.
 *
 * Idempotent on $title — running twice is safe.
 */

// ---- EDIT THESE FOUR LINES ----------------------------------------------
$title         = 'CHANGE ME — human-readable snippet title';
$source_path   = '/tmp/CHANGE-ME-snippet-source.php';   // file the snippet body lives in on the host
$template_id   = 0;                                     // id of an enabled row of the SAME codeType to clone
$snippet_order = 100;                                   // sort order in the admin UI
// -------------------------------------------------------------------------

global $wpdb;
$t = $wpdb->prefix . 'wpcb_snippets';

// 1. Idempotency check.
$existing_id = $wpdb->get_var(
	$wpdb->prepare( "SELECT id FROM $t WHERE title = %s LIMIT 1", $title )
);
if ( $existing_id ) {
	echo "EXISTS:{$existing_id}\n";
	return;
}

// 2. Read the snippet source.
if ( ! file_exists( $source_path ) ) {
	echo "ERR:source file not found: {$source_path}\n";
	return;
}
$code = file_get_contents( $source_path );
if ( false === $code || '' === $code ) {
	echo "ERR:source file empty or unreadable: {$source_path}\n";
	return;
}

// 3. Clone the template row.
if ( ! $template_id ) {
	echo "ERR:set \$template_id to an enabled row id of the same codeType\n";
	return;
}
$row = $wpdb->get_row(
	$wpdb->prepare( "SELECT * FROM $t WHERE id = %d", $template_id ),
	ARRAY_A
);
if ( ! $row ) {
	echo "ERR:template row id {$template_id} not found\n";
	return;
}

// 4. Override the fields that should differ.
unset( $row['id'] );
$row['title']         = $title;
$row['code']          = $code;
$row['original_code'] = $code;
$row['enabled']       = 1;
$row['snippet_order'] = (int) $snippet_order;

// 5. Insert.
$ok = $wpdb->insert( $t, $row );
if ( false === $ok ) {
	echo 'ERR:' . $wpdb->last_error . "\n";
	return;
}
echo "INSERTED:{$wpdb->insert_id}\n";
