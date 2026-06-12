---
name: chunk-large-algolia-records
description: Keep WordPress + Algolia records within Algolia's limits when a document is large — diagnose oversized or silently-rejected records, route long text through the chunked `content` path of wp-search-with-algolia (which splits via Algolia_Utils::explode_content into {post_id}-{i} records collapsed by `distinct`), keep small fields as shared attributes, and for non-plugin or custom-attribute cases deploy a standalone word-boundary chunker. Use when the user says an Algolia record is "too big", "over 100KB", "rejected", "a post is missing from search", "index a long PDF in Algolia", "split large records", "chunk content for Algolia", or "distinct / multiple records per document". Do not use for ordinary relevance tuning, synonyms, or facet config that has nothing to do with record size.
---

# Chunk large records for Algolia (WordPress)

Algolia has two ceilings:

- **100 KB per record — a hard limit.** A record over this is **rejected** by the API
  (HTTP 400). In `wp-search-with-algolia` the rejection is silent at the WP-CLI/admin
  level — the post simply never appears in search.
- **~10 KB per record — the relevance/performance budget.** Algolia recommends keeping
  records small; huge text attributes degrade typo tolerance and ranking.

The answer to both is the same: **split long text into multiple small records that
collapse to one search hit** (`distinct`). This is the standard Algolia large-document
pattern, and `wp-search-with-algolia` already implements it — for the `content` attribute.

## The one rule

> **Big text → the chunked `content` path. Small fields → shared attributes.**

Why: the plugin splits the **`content`** attribute via `Algolia_Utils::explode_content()`
into word-boundary parts (default 2,000 chars, `ALGOLIA_CONTENT_MAX_SIZE`), emitting one
record per part with `objectID = {post_id}-{i}` and `record_index = i`, then sets
`distinct: true` + `attributeForDistinct` so the parts collapse back to a single hit
(best-matching passage wins). See the plugin's
`includes/class-algolia-utils.php` (`explode_content`) and
`includes/indices/class-algolia-searchable-posts-index.php` (records + `get_post_object_id`
+ settings).

**Shared attributes are NOT chunked.** Anything added via
`algolia_searchable_post_shared_attributes` / `algolia_post_shared_attributes` is copied
**whole** onto every chunk record. So a large value in a shared attribute is the *only*
thing that can push a record past 100 KB — and it does so on *every* chunk at once.

## Step 1 — Diagnose

Confirm whether records are missing/oversized and why. With a search-only API key (read
the app id + search key + index name from the plugin's WP options:
`algolia_application_id`, `algolia_search_api_key`, the index e.g.
`{prefix}_searchable_posts`):

```bash
# Is a given post in the index? (the plugin facets on post_id)
curl -fsS -X POST "https://${APP}-dsn.algolia.net/1/indexes/${IDX}/query" \
  -H "X-Algolia-API-Key: ${KEY}" -H "X-Algolia-Application-Id: ${APP}" \
  -d '{"params":"query=&filters=post_id=123&hitsPerPage=0"}'
# nbHits=0 → not indexed. Then check WHY: size, or post type not in the indexed set.
```

Cross-check candidate sizes in WP (LENGTH is bytes; Icelandic chars are multibyte):

```sql
SELECT p.ID, LENGTH(pm.meta_value) bytes
FROM {prefix}posts p
JOIN {prefix}postmeta pm ON pm.post_id=p.ID AND pm.meta_key='<your_attr_meta>'
WHERE p.post_status='publish' AND LENGTH(pm.meta_value) > 90000
ORDER BY bytes DESC;
```

**Distinguish the cause before fixing:** "missing" often means *post type not in the
indexed set* (config), not size. Size-rejection shows as a record present for small posts
of a type but absent only for the large ones of that same indexable type.

## Step 2 — Fix: route long text through the chunked content path

**Preferred — the plugin's own chunker.** Put the long text where it gets split:

```php
// Append long text (extracted PDF text, a denormalized search blob, etc.) to the
// CHUNKED content attribute. The plugin's explode_content() then splits it; distinct
// collapses the chunks back to one hit. Hook BOTH index families if both are used.
function avista_algolia_long_text( WP_Post $post ): string {
  // e.g. extracted PDF text stored in a meta field, or your own search blob:
  return (string) get_post_meta( $post->ID, '_my_long_text', true );
}

add_filter( 'algolia_searchable_post_content', function ( $content, $post ) {
  if ( ! is_a( $post, 'WP_Post' ) ) { return $content; }
  $extra = avista_algolia_long_text( $post );
  return $extra === '' ? $content : trim( (string) $content . ' ' . $extra );
}, 10, 2 );
add_filter( 'algolia_post_content', function ( $content, $post ) {
  if ( ! is_a( $post, 'WP_Post' ) ) { return $content; }
  $extra = avista_algolia_long_text( $post );
  return $extra === '' ? $content : trim( (string) $content . ' ' . $extra );
}, 10, 2 );
```

- Keep only **small** fields (title, url, date, type, a short tag list) as shared
  attributes. Never a multi-KB blob.
- If you need a discrete searchable attribute for ranking (e.g. `unordered(my_blob)`),
  keep a **bounded** copy of it as a shared attribute (cap it, see the WP-prod example in
  the README) AND put the full text in `content` so the tail stays searchable.
- Tune `define( 'ALGOLIA_CONTENT_MAX_SIZE', 8000 );` in `wp-config.php` for fewer, larger
  chunks (still under the 10 KB budget) if you want fewer records.
- `distinct` and stale-chunk cleanup (deleting orphaned `{id}-{n}` when a doc shrinks) are
  handled by the plugin for its content records — you get them for free.

**Long-PDF recipe:** extract the PDF text (e.g. on upload / save) into `post_content` or
a meta field surfaced through the content filter above. A 100-page PDF becomes N small
`{id}-{i}` records, none near 100 KB, returned as one hit with the matching page
highlighted.

## Step 3 — Fix (advanced): a standalone chunker

Use the bundled helper `references/algolia-chunk.php` when you are **not** using
`wp-search-with-algolia` (raw Algolia integration), or you must chunk a **separate**
attribute independently of `content`. It reproduces the same pattern:

- word-boundary split to a byte budget (default 9,000 — under the 10 KB guideline);
- records `objectID = {docId}-{n}`, `record_index = n`, small shared attrs duplicated,
  the chunk text in a `content` field;
- recommended index settings: `attributeForDistinct` + `distinct: true` +
  `customRanking: ['asc(record_index)']`;
- stale-chunk cleanup via `deleteBy` on the doc id (or delete `{id}-{n}` for n ≥ new count)
  before/after saving, so shrinking a doc doesn't leave orphans;
- batched `saveObjects`.

See the file header for a runnable usage example with the Algolia PHP client.

## Step 4 — Verify

```bash
# All chunks of one doc collapse to a single hit under distinct:
curl -fsS -X POST "https://${APP}-dsn.algolia.net/1/indexes/${IDX}/query" \
  -H "X-Algolia-API-Key: ${KEY}" -H "X-Algolia-Application-Id: ${APP}" \
  -d '{"params":"query=&filters=post_id=123&hitsPerPage=50&attributesToRetrieve=objectID,record_index"}'
# Expect several objectIDs (123-0, 123-1, …) with ascending record_index, and the
# front-end search (distinct=true) returning ONE hit for that doc.
```

- Confirm the previously-missing post now returns `nbHits > 0`.
- Confirm a term that only appears late in the long document now matches.
- Confirm no record exceeds your byte budget (re-run the size query / Algolia dashboard).

## Notes / gotchas

- **`distinct` must be enabled on the query too**, not just the index, for the front-end
  to collapse chunks — the plugin sets this for its indices; a custom integration must set
  `attributeForDistinct` in index settings and `distinct: true` (or rely on the index
  default).
- **Shrinking documents leave orphan chunks.** Always clean up stale `{id}-{n}` records on
  reindex; otherwise deleted tail content keeps matching.
- On WPMU DEV / managed hosts there is usually a **persistent object cache** — if you edit
  indexing logic stored in a snippet (WP Code Box), `wp cache flush` before a bulk reindex
  so the fresh code is actually used.
