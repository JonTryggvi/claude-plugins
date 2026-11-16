---
name: kb-handoff
description: Write the end-of-session handoff into the Avista knowledge base (avista-kb) so someone else can continue the work cold — updates the feature's handoff.md (state, open issues, next steps, last session) from this session and the git log, records where code now lives on each site page, creates the feature page from templates if none exists, keeps feature↔site links in both directions, scans for secrets, and commits locally. Use when the user says "hand this off", "write the handoff", "update the KB", "document where this lives", "add this to the knowledge base", "wrap up this feature", "I'm done for today on X", or finishes a work session on a feature others may pick up. Never pushes.
---

# Hand off a feature through the KB

The KB indexes where code lives and what state work is in. A handoff is good when someone who has
never seen the feature can run `kb-pickup` and continue without asking you. Write for that person.

The helper ships with `kb-pickup` in this plugin:

```bash
KB="${CLAUDE_SKILL_DIR}/../kb-pickup/scripts/kb"
KBDIR="$("$KB" where)"
```

Exit 3 `KB_NOT_FOUND`: if the user has the KB somewhere, `"$KB" where --set <path>`. Otherwise stop and
tell them to clone `Avista/avista-kb`.

## Ground rules

- **Write only what you know.** Facts come from this session, `git log`, files you read, and commands
  you ran. If something matters but you don't know it (a config value's location, why something was
  done), write `unknown — ask <name>`. Never guess a path, host or repo.
- **No secrets, no personal SSH usernames.** Credentials go in as `1Password: Shared / <item title>`.
  Paths go in relative to `wp_root`, and `wp_root` relative to home (`~/site/public_html`, never
  `/home/<user>_ssh/…`). Step 6 checks this before committing.
- **Keep frontmatter keys exactly as the templates have them.** Keep `sites:` and `features:` as
  one-line lists (`[a, b]`). The helper's `link` command edits them in place.
- **Never push, never open a PR, never comment on ActiveCollab.** Commit locally and stop. The user
  pushes when they choose.
- **Read README.md in the KB once per session.** It's the source of truth for the conventions. If it
  disagrees with this skill, follow the README and mention it.

## Step 1: which feature

Work out the feature from the session: the repo, the sites touched, what was built. Then:

```bash
"$KB" find "<term>"
```

- **Page exists:** use its slug. Read it with `"$KB" feature <slug>` so you update rather than overwrite,
  and so you see the current KB problems list.
- **No page:** propose a slug (lowercase, dashes) and title to the user in one line, then
  `"$KB" new-feature <slug> "<Title>"` once they agree.

If the session touched more than one feature, do one handoff per feature.

## Step 2: get the KB ready to write

```bash
git -C "$KBDIR" status --porcelain; git -C "$KBDIR" branch --show-current; git -C "$KBDIR" remote
```

- **Dirty tree:** stop and ask. Someone's edits are in progress, and they must not end up in your commit.
- **Has a remote:** `"$KB" sync`, then `git -C "$KBDIR" switch -c handoff/<slug>-<YYYY-MM-DD>`. The
  handoff goes in for review as a branch.
- **No remote (local KB):** commit on `main`.

## Step 3: gather what happened

Collect, don't summarise yet:

- **This session:** what was changed, on which site or repo, at which path, and what's left half-done.
- **Git:** for each repo worked in,
  `git log --since="<handoff's previous updated: date>" --format="%h %ad %an %s" --date=short`. Use the
  whole log if it's a new page. Also `git status -sb`. Unpushed commits mean `lives:` is not `repo` yet.
- **Server-only work:** for code changed over SSH, the host, the path relative to `wp_root`, and
  whether it's in any repo now.
- **ActiveCollab:** the task or project URL if the session used one. It goes into the overview's
  `activecollab:` list.

## Step 4: write the pages

**`features/<slug>/handoff.md`.** Rewrite the sections; git keeps the history.
- Frontmatter: `updated:` today, `by:` the user's name (`git config user.name`).
- **State:** what works now, per site, as of today.
- **Open issues:** bugs, risks, things that look wrong. One line each.
- **Next steps:** numbered and concrete enough to act on: what, where, and how you'll know it's done.
- **Last session:** what changed and where (site, path, repo, commit hashes). Include anything left
  half-done, e.g. "edited on server, not committed".

**`features/<slug>/overview.md`.** Change only what changed. For a new page, fill in what you know:
- `owner:`, `status:`, `repos:`, `activecollab:` frontmatter.
- The components table: one row per piece (plugin, theme file, Code Box snippet, cron job, external
  service), with path relative to `wp_root`.
- Configuration: where each setting lives and which sites differ. 1Password references only.
- Decisions: why, if the session showed it. A choice that affects other features gets its own
  `decisions/NNNN-<title>.md` from `templates/decision.md`.

**Site pages**, for every site the feature runs on:

```bash
"$KBDIR/scripts/seed-sites.sh" <domain>   # only if sites/<domain>.md is missing; never overwrites
"$KB" link <slug> <domain>                # adds both directions; safe to repeat
```

Then edit the site page's `code:` block so it records where the code is now, one entry per path:

```yaml
code:
  - path: wp-content/plugins/avista-algolia
    what: Algolia indexer
    lives: server-only         # server-only | repo | both
    repo: null                 # Avista/<Client>-WP once pushed
```

Fill a `null` `ssh_host` or `wp_root` only if this session confirmed the value. Run `"$KB" touch <file>`
on every page you edited by hand.

## Step 5: check the result

```bash
"$KB" feature <slug>
```

The KB problems list should be shorter than in step 1. Fix any one-way link or missing site page you
caused. Leave `server-only` entries listed. They're true, and they're the cleanup queue.

## Step 6: secret and path scan

```bash
git -C "$KBDIR" add -A && git -C "$KBDIR" diff --cached | grep -nEi \
  '(^|[^0-9a-z])(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^ <`]|BEGIN [A-Z ]*PRIVATE KEY|/home/[^/ ]+/|_ssh\b|sk_(live|test)_|AKIA[0-9A-Z]{16}'
```

Any hit: fix the line (1Password reference, or `~/`-relative path), re-stage, and re-run. Don't commit
until it is clean. Never echo the matched value back to the user; name the file and line.

## Step 7: commit and report

```bash
git -C "$KBDIR" commit -m "docs(<slug>): handoff <YYYY-MM-DD>"
```

End the commit message with the session's attribution line, if one is set. Then tell the user:
- which pages changed, with a one-line summary each;
- the branch name, if it's on a branch (they push and open the PR when they choose);
- the KB problems still open, and in particular which code is still server-only.
