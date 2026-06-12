# avista-wp-algolia-chunker

Keep WordPress + Algolia records within Algolia's limits when a document is large — a long
post body, a denormalized search blob, or extracted PDF text. A 20–100 page PDF easily
exceeds Algolia's **100 KB hard per-record limit** (records above it are silently
rejected — the post just disappears from search), and anything over ~10 KB hurts
relevance.

## The one rule

> **Big text → the chunked `content` path. Small fields → shared attributes.**

`wp-search-with-algolia` already splits the **`content`** attribute into word-boundary
parts (`Algolia_Utils::explode_content`, default 2,000 chars / `ALGOLIA_CONTENT_MAX_SIZE`),
emitting one `{post_id}-{i}` record per part with `record_index`, and collapsing them back
to a single hit via `distinct`. **Shared attributes are copied whole onto every chunk and
are never split** — so a multi-KB value in a shared attribute is the one thing that can
blow the 100 KB limit. Route long text through `content`; keep only small fields as shared
attributes.

## Skills

| Skill | Purpose |
|---|---|
| [`chunk-large-algolia-records/`](skills/chunk-large-algolia-records/) | Diagnose oversized/missing records, route long text through the chunked `content` path, keep discrete searchable attributes bounded, and (for non-plugin / custom-attribute cases) deploy the standalone `{id}-{n}` `distinct` chunker. Includes a ready-to-use PHP helper. |
| [`avista-wp-algolia-chunker-overview/`](skills/avista-wp-algolia-chunker-overview/) | Summary of this plugin — the rule, the skill, when to use it. Run `/avista-wp-algolia-chunker-overview` or ask "what does this plugin do?". |

## When this plugin gets used

Trigger phrases the skill watches for:

- "Algolia record too big / over 100KB / rejected"
- "a post is missing from Algolia search"
- "index a long PDF in Algolia"
- "split large records" / "chunk content for Algolia"
- "distinct / multiple records per document"

## Worked example — capping a shared search blob (WP Code Box / functions.php)

When a denormalized blob (e.g. an ACF-derived `acf_search_string`) is a discrete
searchable attribute you want to keep for ranking, bound the shared copy and push the full
text through the chunked content path so the tail stays searchable:

```php
if ( ! defined( 'AVISTA_ACF_SEARCH_SHARED_MAX' ) ) {
  define( 'AVISTA_ACF_SEARCH_SHARED_MAX', 80000 ); // bytes; headroom under Algolia's 100KB
}

// 1) Bound the shared attribute (no effect below the threshold).
add_filter( 'algolia_searchable_post_shared_attributes', function ( array $attrs, $post ) {
  if ( ! is_a( $post, 'WP_Post' ) ) { return $attrs; }
  $blob = (string) get_post_meta( $post->ID, '_my_blob', true );
  if ( strlen( $blob ) > AVISTA_ACF_SEARCH_SHARED_MAX ) {
    $cut  = mb_strcut( $blob, 0, AVISTA_ACF_SEARCH_SHARED_MAX, 'UTF-8' );
    $sp   = strrpos( $cut, ' ' );
    $blob = false !== $sp ? substr( $cut, 0, $sp ) : $cut;
  }
  $attrs['my_blob'] = $blob;
  return $attrs;
}, 10, 2 );

// 2) Only when oversized, append the full text to the CHUNKED content path.
$append = function ( $content, $post ) {
  if ( ! is_a( $post, 'WP_Post' ) ) { return $content; }
  $blob = (string) get_post_meta( $post->ID, '_my_blob', true );
  if ( strlen( $blob ) <= AVISTA_ACF_SEARCH_SHARED_MAX ) { return $content; }
  return trim( (string) $content . ' ' . $blob );
};
add_filter( 'algolia_searchable_post_content', $append, 10, 2 );
add_filter( 'algolia_post_content', $append, 10, 2 );
```

For non-plugin / raw Algolia integrations, use
[`skills/chunk-large-algolia-records/references/algolia-chunk.php`](skills/chunk-large-algolia-records/references/algolia-chunk.php).

## Limits cheat-sheet

| Limit | Value | Behaviour |
|---|---|---|
| Per-record hard limit | 100 KB | Record rejected (HTTP 400) |
| Per-record relevance budget | ~10 KB | Degraded typo tolerance / ranking |
| `explode_content` default chunk | 2,000 chars | `ALGOLIA_CONTENT_MAX_SIZE` to change |
| Standalone chunker default | 9,000 bytes | `Avista_Algolia_Chunker::DEFAULT_MAX_BYTES` |
