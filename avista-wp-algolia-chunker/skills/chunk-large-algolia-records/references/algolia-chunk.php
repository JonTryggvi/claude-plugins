<?php
/**
 * Avista_Algolia_Chunker — split long text into multiple small Algolia records that
 * collapse to a single search hit via `distinct`. Framework-agnostic; use it when you are
 * NOT relying on wp-search-with-algolia's built-in content splitting (raw Algolia
 * integration), or when you must chunk an attribute independently of `content`.
 *
 * Mirrors the proven pattern: word-boundary split to a byte budget, records
 * `{docId}-{n}` with an ascending `record_index`, small shared attributes duplicated on
 * each chunk, and index settings (`attributeForDistinct` + `distinct` +
 * `customRanking: ['asc(record_index)']`) that collapse the chunks back to one hit.
 *
 * Limits this respects:
 *   - 100 KB per record: HARD limit, Algolia rejects above it (HTTP 400).
 *   - ~10 KB per record: relevance/performance budget. Default chunk = 9 KB of text,
 *     leaving headroom for shared attributes + JSON overhead.
 *
 * --- USAGE (Algolia PHP client v3/v4) ---------------------------------------------------
 *
 *   use Algolia\AlgoliaSearch\SearchClient;
 *
 *   $client = SearchClient::create($appId, $adminApiKey);
 *   $index  = $client->initIndex('my_docs');
 *
 *   // One-time: settings that make chunks behave as one document.
 *   $index->setSettings(Avista_Algolia_Chunker::recommendedSettings('doc_id'));
 *
 *   // Per document:
 *   $docId  = (string) $post->ID;
 *   $shared = [
 *     'doc_id'    => $docId,
 *     'title'     => get_the_title($post),
 *     'url'       => get_permalink($post),
 *     'post_type' => $post->post_type,
 *   ];
 *   $records = Avista_Algolia_Chunker::buildRecords($docId, $longText, $shared);
 *
 *   // Replace cleanly: drop any previous chunks for this doc, then save the new ones.
 *   $index->deleteBy(['filters' => 'doc_id:' . $docId]); // requires doc_id in attributesForFaceting
 *   if ($records) { $index->saveObjects($records); }     // saveObjects batches automatically
 *
 * ----------------------------------------------------------------------------------------
 *
 * PHP 8.0+. No WordPress dependency.
 */
final class Avista_Algolia_Chunker {

  /** Default per-chunk text budget in bytes (under Algolia's ~10 KB relevance guideline). */
  public const DEFAULT_MAX_BYTES = 9000;

  /**
   * Split text into word-boundary chunks no larger than $maxBytes (byte length, so it is
   * safe for multibyte UTF-8). Continuation chunks are prefixed with "… " for readable
   * snippets. Returns at least one chunk (possibly empty) so callers always get a record.
   */
  public static function chunk(string $text, int $maxBytes = self::DEFAULT_MAX_BYTES): array {
    $text = trim($text);
    if ($maxBytes < 1) {
      $maxBytes = self::DEFAULT_MAX_BYTES;
    }

    $parts  = [];
    $prefix = '';
    while (true) {
      $text = trim($text);
      if (strlen($text) <= $maxBytes) {
        $parts[] = $prefix . $text;
        break;
      }

      // Cut at the last space at or before the budget; fall back to a hard cut.
      $window      = mb_strcut($text, 0, $maxBytes, 'UTF-8');
      $cut         = strrpos($window, ' ');
      $cut         = false !== $cut ? $cut : strlen($window);
      $parts[]     = $prefix . substr($text, 0, $cut);
      $text        = substr($text, $cut);
      $prefix      = '… ';
    }

    return $parts;
  }

  /**
   * Build Algolia records for one document. Each record carries the $shared attributes
   * plus `content` (the chunk), `objectID` = "{docId}-{n}", and `record_index` = n.
   *
   * @param array<string,mixed> $shared Small, per-document attributes (title, url, etc.).
   *                                     Keep these small — they are duplicated on every chunk.
   * @return array<int,array<string,mixed>>
   */
  public static function buildRecords(
    string $docId,
    string $text,
    array $shared = [],
    int $maxBytes = self::DEFAULT_MAX_BYTES
  ): array {
    $records = [];
    foreach (self::chunk($text, $maxBytes) as $i => $part) {
      $records[] = $shared + [
        'objectID'     => $docId . '-' . $i,
        'record_index' => $i,
        'content'      => $part,
      ];
    }

    return $records;
  }

  /**
   * Recommended index settings so chunks of one document collapse to a single hit.
   * Merge with your own searchableAttributes / ranking as needed.
   *
   * @return array<string,mixed>
   */
  public static function recommendedSettings(string $distinctAttribute = 'doc_id'): array {
    return [
      'attributeForDistinct'  => $distinctAttribute,
      'distinct'              => true,
      // Within a document, prefer the earliest matching chunk for a stable snippet.
      'customRanking'         => ['asc(record_index)'],
      // distinctAttribute must be filterable for deleteBy()-based stale-chunk cleanup.
      'attributesForFaceting' => ['filterOnly(' . $distinctAttribute . ')'],
    ];
  }
}
