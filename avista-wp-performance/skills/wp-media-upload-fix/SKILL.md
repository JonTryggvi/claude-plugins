---
name: wp-media-upload-fix
description: Diagnose and fix slow media uploads on an Avista WordPress site — the "a tiny image takes ~30 seconds to upload to the media library" complaint. Root cause on this stack is Smush Pro optimizing every upload synchronously against a remote API (wp-smush-settings auto:true + lossy "Super-Smush" + optimize-original + WebP across ~10 registered image sizes) — a blocking HTTPS round-trip per size, inline in the upload request, which also pins a PHP worker for the whole ~30s and starves the front end (so slow uploads and slow pages spike together). The fix turns off optimize-on-upload after backing up the full setting, and REQUIRES scheduling a background/bulk smush so the library stays optimized (otherwise you trade upload speed for page weight); it also surfaces the secondary cost — WordPress generating N subsizes + WebP per upload — with levers to trim it. Use when the user says "uploads are slow", "uploading images takes 30 seconds", "the media library is slow", "Smush is slow", "a small image takes forever to upload", "async-upload is slow", or after wp-perf-audit sees async-upload.php in php_slow.log. Approval-gated: backs up wp-smush-settings first, changes one setting on explicit OK, verifies with a timed test import before/after, ships a one-line rollback, and is NOT done until the bulk-smush follow-up is set up.
---

# WP media upload fix — Smush synchronous optimization + image-size sprawl

The client uploads a 169 KB image and waits ~30s. On this stack the cause is **Smush optimizing on upload, synchronously, against a remote API**: with `auto:true` + `lossy:"1"` (Super-Smush → WPMU DEV API) + `original:true` + `webp_direct_conversion:true` across ~10 registered image sizes, one upload becomes a sequential blocking HTTPS round-trip *per size* + the original + WebP, all inline in the upload request. Two harms: the editor waits tens of seconds, **and** each upload pins a PHP worker for ~30s — so an editor uploading to the media bank starves the front end, turning a 4s article MISS into a 30–60s one at the same moment. That's why the "slow upload" and "slow news" complaints coincide.

This changes production: follow the [`avista-wp-prod-ops`](../../../avista-wp-prod-ops/) posture (inspect, back up, deploy on explicit approval, verify, rollback).

## Step 1 — Diagnose (read-only) and reproduce

```bash
# The Smush config — look for auto / lossy / original / webp:
$SSH "cd ~/site/public_html && wp option get wp-smush-settings --format=json"
# How many subsizes get generated per upload (the secondary cost):
$SSH "cd ~/site/public_html && wp eval '\$s=wp_get_registered_image_subsizes(); \
  echo count(\$s).\" subsizes: \".implode(\", \", array_keys(\$s)).\"\n\";'"
# Confirm uploads are actually in the slow path:
$SSH "grep -c async-upload.php ~/site/logs/php_slow.log 2>/dev/null || echo 0"
```

Reproduce with a **timed test import** so you have a real before-number (not a guess). Put a sample image on the host and time it:

```bash
scp sample.jpg <user>@<host>:~/sample.jpg
$SSH "cd ~/site/public_html && time wp media import ~/sample.jpg --porcelain"   # note the seconds + the new attachment ID
```

On the audited site a 482 KB import took **19.3s** with Smush auto on. Delete the throwaway attachment afterwards (`wp post delete <id> --force`) so you don't litter the library.

## Step 2 — Back up the setting (it's the only version history)

`wp-smush-settings` is a serialized option, not a file — there's no other history. Snapshot the full option before touching it:

```bash
$SSH "cd ~/site/public_html && wp option get wp-smush-settings --format=json" \
  > production-notes/backups/wp-smush-settings.before.json
cat production-notes/backups/wp-smush-settings.before.json   # sanity-check it's real JSON, not empty
```

## Step 3 — Apply the fix (only after approval)

Turn off optimize-on-upload. Nothing else changes; flush the object cache so the new setting is live:

```bash
$SSH "cd ~/site/public_html && wp option patch update wp-smush-settings auto false && wp cache flush"
# Confirm it took (auto should now be false/0):
$SSH "cd ~/site/public_html && wp option get wp-smush-settings --format=json" | grep -o '\"auto\":[^,]*'
```

If `patch update` coerces the type oddly (some Smush builds store `auto` as a string), re-read and, if needed, restore-then-re-patch from the JSON backup. The reliable source of truth for the value is the backup you took in step 2.

## Step 4 — MANDATORY follow-up: schedule a bulk/background smush

**The fix is not complete until this is done.** With `auto` off, *new* uploads are no longer optimized — leave it there and you've traded upload speed for page weight (heavier images → slower pages → you've moved the problem). Existing images keep their optimization + WebP; only new ones need catching up. Set up one of:

- **Smush UI → Bulk Smush** run now, and enable Smush's background/scheduled optimization if the plan offers it (so uploads return immediately but still get optimized out-of-band), **or**
- a **nightly WP-CLI bulk pass** via real cron, e.g. `wp smush bulk` (confirm the exact subcommand for the installed Smush version) scheduled from the host's crontab / WPMU DEV scheduler.

Confirm with the user which one they want and that it's actually scheduled before you call this skill done. Note it in the deploy record.

## Step 5 — Verify (timed before/after)

```bash
$SSH "cd ~/site/public_html && time wp media import ~/sample.jpg --porcelain"   # note ID + seconds
# The Smush stats meta should be ABSENT now (proves it didn't optimize inline):
$SSH "cd ~/site/public_html && wp post meta get <new-attachment-id> wp-smush-stats 2>/dev/null || echo 'no wp-smush-stats meta (correct — Smush did not run inline)'"
$SSH "cd ~/site/public_html && wp post delete <new-attachment-id> --force"
$SSH "rm -f ~/sample.jpg"
```

Expected (matches the audited fix): import time drops sharply (audited: 19.3s → 8.5s), `wp-smush-stats` meta absent. Real small uploads, with workers also freed by `wp-bot-mitigation`, should now be a few seconds.

## Step 6 — The remaining cost (optional, needs analysis)

After Smush, the leftover upload time is **WordPress generating the registered subsizes + WebP** per upload. If uploads still need to be faster, two levers (each with a tradeoff — analyze before doing):

- **Trim registered image sizes** to only those the theme/Breakdance actually uses. Fewer sizes = faster uploads + less disk, but you must confirm nothing references a size before removing it (broken `srcset`/layout otherwise).
- **Defer WebP generation off the upload path** (turn off `webp_direct_conversion`, generate WebP in the bulk pass). Tradeoff: brand-new images lack WebP until the bulk run catches them.

These are follow-ups, not part of the core fix — flag them, don't bundle them in without the user's sign-off.

## Step 7 — Record the rollback

Mirror `production-notes/smush-upload-fix.md` (problem, change, verification numbers, the required bulk follow-up, rollback). Rollback re-enables optimize-on-upload:

```bash
# Simplest: re-enable "Automatically optimize new uploads" in the Smush UI. Or via SSH:
$SSH "cd ~/site/public_html && wp option patch update wp-smush-settings auto true 2>/dev/null || \
      wp option update wp-smush-settings --format=json < production-notes/backups/wp-smush-settings.before.json"
```

## Guardrails

- **Not done until the bulk-smush follow-up is scheduled** (step 4). This is the non-negotiable — turning `auto` off alone silently degrades page weight over time.
- **Approval-gated**, with a real backup of the serialized option (step 2) since there's no other history.
- **Verify with a timed import**, not by assertion — the before/after seconds and the absent `wp-smush-stats` meta are the proof.
- Clean up throwaway test attachments and the sample file so the fix leaves no litter.
