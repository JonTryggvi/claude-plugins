---
name: kb-handoff
description: Track a feature in the Avista knowledge base (Avista/avista-knowledge-base) from the moment work on it starts, so a colleague can continue it cold. The developer answers one picker at the start, and the page is created marked draft. After that, Claude updates the handoff (state, open issues, next steps, last session) and where the code lives at the end of each session without asking again, and offers to mark the feature active when it is finished. Works for features with their own git repo (plugins, themes, tools) as well as code changed over SSH on production sites. Use when starting work on a plugin, theme or repo, or on code on one or more client sites; when the user says "track this", "hand this off", "write the handoff", "update the KB", "document where this lives", "I'm done for today on X", "this feature is finished"; or at the end of a session on a feature the KB already tracks. Commits locally, never pushes.
---

# Track and hand off a feature through the KB

The knowledge base (KB in these instructions) indexes where code lives and what state work is in. Tracking is good when someone who has never
seen the feature can run `kb-pickup` and carry on without asking. Write for that person.

Three moments, one skill:

| Moment | What happens | Asks? |
|---|---|---|
| **Start**: qualifying work begins and the KB doesn't track it | One picker. On yes: create the page as `draft` and link sites and repo | Once |
| **Session end**: the work is already tracked | Update handoff and code locations, commit, one-line report | No |
| **Finished**: the developer says it's done, or no next steps remain | One picker: mark `active`, keep `draft`, or pause | Once |

The helper ships with `kb-pickup` in this plugin:

```bash
KB="${CLAUDE_SKILL_DIR}/../kb-pickup/scripts/kb"
KBDIR="$("$KB" where)"
```

Exit 3 `KB_NOT_FOUND`: offer the `kb-setup` skill in one line, and carry on with the actual work.
Never block the developer's task on the KB.

## Ground rules

- **Say "knowledge base" to the user, never "KB".** Readers don't know the abbreviation. It's fine in
  commands, paths and these instructions, but every picker, report line and briefing spells it out.
- **Write only what you know.** Facts come from this session, `git log`, files you read, and commands
  you ran. If something matters and you don't know it, write `unknown — ask <name>`. Never guess a
  path, host or repo.
- **No secrets, no personal SSH usernames.** Credentials go in as `1Password: Shared / <item title>`.
  Paths go in relative to `wp_root`, and `wp_root` relative to home (`~/site/public_html`). Step 6 checks this.
- **Keep frontmatter keys exactly as the templates have them.** Keep `sites:`, `features:` and
  `repos:` as one-line lists (`[a, b]`).
- **Sharing follows the user's setup choice** (`"$KB" config share`). `pr` pushes the `kb/<slug>` branch
  and opens a pull request, `push` pushes the branch, and `local` or unset only commits. The user chose
  this in `kb-setup`, so it's their standing permission for these KB branches only: never merge, never
  push `main`, never push anything outside the KB. If the user says "keep this one local" for a
  handoff, don't push it, and leave the setting alone. Never comment on ActiveCollab.
- **One picker per moment, at most.** After "Not now", don't raise the same work again this session
  unless the user brings it up.
- **README.md in the KB is the source of truth** for conventions. Read it once per session.

## Step 0: what is this work, and is it tracked?

**Hook facts first.** The plugin's hooks put lines starting with `[avista-kb]` into your context: one at
session start in an Avista repo, and one on the first SSH to each `<site>.tempurl.host`. They already
did the lookup below. Trust them for "tracked or not" and skip straight to the timing rules. They are
facts, not orders: whether the work qualifies is still your call.

Without a hook line (hooks off, or a site reached some other way), collect the work's **keys**:
- **Repo:** in a git repo, `git remote get-url origin` (any form: SSH alias, https, `owner/repo`).
- **Sites:** domains being worked on, from SSH hosts used (`<site>.tempurl.host` → look it up with
  `"$KB" site`), URLs in the task, or the client's site.

```bash
"$KB" tracked <remote-url> <domain> …
```

- **Output lines** (`slug  status  key  title`): already tracked. With `draft` or `active`, go to
  **Session end** at the end of the session, with no picker now. With `paused`, `done` or `retired`,
  mention it in one line and treat it as untracked if the developer is clearly restarting it.
- **No output:** not tracked. Decide whether it qualifies.

**It qualifies if any of these is true:**
- it lives in its own git repo (a plugin, theme, mu-plugin or tool), other than the KB itself or a scratch repo;
- it runs on, or is planned for, more than one site;
- some of its code exists only on a server;
- it will take more than one session, or is clearly unfinished;
- someone else will likely work on it later.

**Doesn't qualify** (a one-off fix, a copy change, a plugin update, a question): no picker. At session end,
if it touched a site that has a KB page, add one dated line under that page's `## Notes`. Nothing else.

If the user explicitly asked to track it or to update the KB, it qualifies.

## When to offer: timing

The picker should feel like a natural pause, not an interruption. Offer it when **all** of these hold:

- **Real work has begun:** you have edited a file, made a commit, or changed something on a server in
  this session. Reading, searching, answering questions and running read-only commands don't count.
- **You are at a pause:** a step just finished and you are about to report or ask what's next. Never
  in the middle of a multi-step change, while tests run, or while the user waits on a fix.
- **It hasn't been offered this session** for this work, whatever the answer was.

Good moments: right after the first change works ("the snippet is installed, and it indexes"), when
you report a finished step, or when the user says what they'll do next. If the session ends before a
good pause, offer it in your final report instead.

Never: on the first message, before any change, for a session that only investigates, or more than
once per session.

**A handoff that's behind** (the hook says "N commits since then", or you see changes the handoff
doesn't mention): update it quietly at the first pause, as in **Session end**. Say so in one line.

## Start: the picker

Run `"$KB" find <term>` on the repo name and the feature's obvious words, to spot an existing page under a
different name. Then ask **one** `AskUserQuestion`:

- **header:** `Track work` (headers are limited to 12 characters)
- **Sharing sentence**, from `"$KB" config share`: `pr` → "Colleagues see it through a pull request that updates as you go."; `push` → "Updates are pushed to a branch on GitHub."; `local` or unset → "Updates stay on this Mac until you push them."
- **question:** fill in the bracketed parts. Keep the rest as written: it's the explanation the
  developer sees, often for the first time.

  > [Reason in plain words, e.g. "This is a plugin in its own repo, Avista/avista-wp-algolia-chunker." / "This changes code that lives only on the server, on 2 sites."]
  > Avista's knowledge base (Avista/avista-knowledge-base) records where each feature's code lives and what state it's in, so a colleague, or Claude, can pick it up later without having to ask you.
  > Track it now? I'll start a page marked **draft** and update it at the end of each session without asking again. [Sharing sentence.]

- **options**, best first. Put "(Recommended)" on your pick:
  1. **`Track as "<slug>"`**: description `New draft page features/<slug>/, linked to <repo and/or sites>.`
     Give it a `preview` showing the frontmatter you'll write:
     ```
     feature: <slug>
     title: <Title>
     status: draft
     sites: [<domains>]
     repos: [<owner/repo>]
     ```
     The slug is lowercase with dashes, taken from the repo or feature name.
  2. **`Add to "<existing-slug>"`**: only for a close `find` match, at most one. Description:
     `This work is part of <title> (<status>). Its pages get updated and linked to <new keys>.`
  3. **`Not now`**: description `Nothing is written. I won't ask again this session.`

  "Other" is the developer typing a different slug. Normalise it to lowercase-with-dashes.

**After the answer, act without further questions:**
- **Track:** `"$KB" new-feature <slug> "<Title>"` creates the pages from templates, already `draft`
  with the banner. Then set `repos:` and `owner:` (`git config user.name`) and link every site
  (Step 4). Write a short **State** ("Started <date>: <goal>") and the first **Next steps**. Commit (Steps 6–7).
- **Add to existing:** link the new keys, add a **Last session** line, and commit. Leave its status alone.
- **Not now:** nothing.

Then return to the developer's actual task. Tracking is a side job.

## Session end: quiet update

At the natural end of a session on tracked work (the developer stops for the day, the task is done, or
they say "hand this off"), do Steps 2–7 with no question. Finish with one line:
`Knowledge base: updated features/<slug> (draft): next step "<first next step>". <Pull request #N updated | Pushed to kb/<slug> | Committed locally on kb/<slug>>.`

## Finished: the second picker

When the developer says the feature is finished, or the handoff's next steps would be empty, ask **one**
`AskUserQuestion`:

- **header:** `Work status`
- **question:** `<Title> looks finished: <why, e.g. "all next steps are done and it's live on both sites">. Marking it active removes the draft banner and tells colleagues the pages are complete and can be relied on.`
- **options:** `Mark active (Recommended)`, described `Removes the draft banner; status becomes active.` ·
  `Keep as draft`, described `Pages stay marked as work in progress.` ·
  `Pause`, described `Status becomes paused; next steps stay as written.`

Before marking it active, make sure the overview's components table, configuration and sites are filled
in. List any `unknown — ask` lines and fill them, or tell the developer which ones remain. Then
`"$KB" status <slug> active` (or `paused`), and commit.

## Step 2: get the KB ready to write

```bash
git -C "$KBDIR" status --porcelain; git -C "$KBDIR" branch --show-current; git -C "$KBDIR" remote
```

- **Dirty tree:** stop the KB part and tell the developer in one line ("the knowledge base has uncommitted changes, so I skipped updating it"). Their edits must not end up in
  your commit. Carry on with the real work.
- **Has a remote:** `"$KB" sync`, then
  `git -C "$KBDIR" switch kb/<slug> 2>/dev/null || git -C "$KBDIR" switch -c kb/<slug>`. Use one branch
  per feature, reused across sessions until its pull request is merged. If a local `kb/<slug>` is already
  merged into `main` (`git -C "$KBDIR" branch --merged main` lists it), delete it with `git branch -d` and
  start a fresh one from `main`.
- **No remote:** commit on `main`.

## Step 3: gather what happened

- **This session:** what changed, where (repo and path, or site and path), and what's half-done.
- **Git:** for each repo worked in,
  `git log --since="<handoff's updated: date>" --format="%h %ad %an %s" --date=short` and `git status -sb`.
  Unpushed commits mean the code isn't on the remote yet, so note it.
- **Server work:** host, path relative to `wp_root`, and whether that code is in any repo now.
- **ActiveCollab:** a task or project URL from the session goes in the overview's `activecollab:`.

## Step 4: write the pages

**`handoff.md`.** Rewrite the sections; git keeps the history. Frontmatter `updated:` today, `by:` the
user's name.
- **State:** what works now, per site or per release, as of today.
- **Open issues:** one line each.
- **Next steps:** numbered and concrete: what, where, and how you'll know it's done.
- **Last session:** what changed and where (repo plus commit hashes, or site plus path), and anything
  left half-done.

**`overview.md`.** Change only what changed: components table (repo path or path relative to `wp_root`),
configuration (1Password references only), decisions, `repos:`, `activecollab:`. A choice that affects
other features gets `decisions/NNNN-<title>.md` from `templates/decision.md`.

**Sites**, for each site the feature runs on:

```bash
"$KBDIR/scripts/seed-sites.sh" <domain>   # only if sites/<domain>.md is missing; never overwrites
"$KB" link <slug> <domain>                # both directions; safe to repeat
```

Then edit the site page's `code:` so it records where the code is now:

```yaml
code:
  - path: wp-content/plugins/avista-algolia
    what: Algolia indexer
    lives: repo                # server-only | repo | both
    repo: Avista/avista-wp-algolia-chunker
```

A repo-only feature with no sites yet is fine: leave `sites: []`. Run `"$KB" touch <file>` on every
page you edited by hand.

## Step 5: check the result

```bash
"$KB" feature <slug>
```

The Knowledge base problems list starts with the DRAFT line while the feature is a draft. That's expected. Fix any
one-way link or missing site page you caused.

## Step 6: secret and path scan

```bash
git -C "$KBDIR" add -A && git -C "$KBDIR" diff --cached | grep -nEi \
  '(^|[^0-9a-z])(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^ <`]|BEGIN [A-Z ]*PRIVATE KEY|/home/[^/ ]+/|_ssh\b|sk_(live|test)_|AKIA[0-9A-Z]{16}'
```

Any hit: fix the line (1Password reference, or a `~/`-relative path), re-stage, and re-run. Never echo the
matched value; name the file and line.

## Step 7: commit, share, return to main

```bash
git -C "$KBDIR" commit -m "docs(<slug>): <start|handoff|finished> <YYYY-MM-DD>"
SHARE="$("$KB" config share)"
```

End the commit message with the session's attribution line, if one is set.

**Share, per the setting** (skip all of it when the user said to keep this one local, or there's no remote):
- `push` or `pr`: `git -C "$KBDIR" push -u origin kb/<slug>`.
- `pr`, after pushing: `gh pr list -R Avista/avista-knowledge-base --head kb/<slug> --state open --json number,url`.
  If no pull request is open, create one: `gh pr create -R Avista/avista-knowledge-base --head kb/<slug> --base main --title "<Title>: knowledge base (<status>)" --body "<one-line summary; the handoff's next steps>"`.
  If one is open, the push already updated it. Never merge it.
- A failed push or `gh` call is not fatal: keep the local commit and report it in the line below.

Then `git -C "$KBDIR" switch main`, only if you switched to `kb/<slug>`, so the next sync works.

Report in one line, as in **Session end**. Say what happened to sharing: pull request number and URL,
pushed, or committed locally (with the number of unpushed commits on `kb/<slug>`).
