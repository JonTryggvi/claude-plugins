---
name: kb-setup
description: Set up the avista-kb plugin on this Mac with as little effort from the user as possible — checks what is already in place, asks the few real choices in a single dialog, then clones the Avista knowledge base, saves its location, adds the knowledge base rules to ~/.claude/CLAUDE.md, chooses how handoffs reach colleagues (push and open a pull request automatically, push only, or keep local), and confirms the plugin's hooks are running. Use right after installing avista-kb, when the plugin's hook says it isn't set up, or when the user says "set up the knowledge base", "set up avista-kb", "the knowledge base isn't cloned", "kb setup", or "change how handoffs are shared". Safe to re-run; it only fixes what is missing.
---

# Set up avista-kb

Goal: the user answers **one** dialog and Claude does everything else. Don't explain steps the user
doesn't need to act on. Report what was done at the end.

```bash
KB="${CLAUDE_SKILL_DIR}/../kb-pickup/scripts/kb"
"${CLAUDE_SKILL_DIR}/scripts/preflight.sh"
```

`preflight.sh` is read-only and prints `key=value` lines. Everything below is decided from them.

## Ground rules

- **Say "knowledge base" to the user, never "KB".**
- **Do the work yourself.** The only steps the user must do are ones that need their password or a
  browser: `gh auth login`, unlocking 1Password. Give them the exact command, wait, then re-run preflight.
- **Never overwrite.** Don't touch an existing clone that has uncommitted changes, and append to
  `~/.claude/CLAUDE.md` rather than rewriting it.
- **Re-running is normal.** If everything is already in place, say so in one line and stop.

## Step 1: blockers (rare)

- `tools=` lists something missing: name it and point to the `setup-dev-machine` skill (avista-dev-machine).
  Stop.
- `gh_sees_kb=no`:
  - If `gh_accounts` lists an org account (the `<name>Avista` one) that isn't active,
    `gh auth switch --user <it>` and re-run preflight. Say which account is now active.
  - If no account can see it, the user must run `gh auth login` in their own terminal with their Avista
    GitHub account, or ask an org admin for access to `Avista/avista-knowledge-base`. Stop until done.

## Step 2: the one dialog

Ask a **single** `AskUserQuestion` with only the questions that apply. Each question is skipped when its
answer is already known.

1. **Where to clone**: only when `kb_path=none`. Header `Location`.
   Question: `Where should I put the Avista knowledge base? It's a small git repo of markdown pages.`
   Options: `<default_dir> (Recommended)` (description: "Next to your other projects"), and the other of
   `~/Dropbox/dev/…` or `~/dev/…`. "Other" is a path they type.
2. **Sharing**: only when `share=` is empty. Header `Sharing`.
   Question: `When I write a handoff at the end of a session, how should it reach your colleagues?`
   - `Push and open a pull request (Recommended)`: "Each feature gets one pull request that updates
     as you work. Colleagues see it without you doing anything."
   - `Push the branch only`: "The branch is on GitHub; you open the pull request when you want."
   - `Keep it local`: "Nothing leaves this Mac until you push it yourself."
3. **Rules file**: only when `claude_md=no`. Header `Reminders`.
   Question: `Add a short section to your ~/.claude/CLAUDE.md so Claude checks the knowledge base when you start work? It's a backup in case the plugin's hooks don't run.`
   Options: `Add it (Recommended)` (description: shows the section in a preview), `Skip`.
   Give the first option a `preview` with the contents of `references/claude-md-section.md`.

If no question applies, skip the dialog.

## Changing a choice later

When the user wants to change something ("change how handoffs are shared", "stop pushing my handoffs",
"open pull requests automatically", "move the knowledge base", "remove the CLAUDE.md section"), skip
Step 1's checks that don't apply. Ask **only that question**, with the current choice labelled
`(current)` and listed first. Then apply it:

- **Sharing:** `"$KB" config share <new>`. Takes effect from the next handoff. Nothing already
  pushed is undone.
- **Location:** move the folder (`mv`) if they want it moved, then `"$KB" where --set <new>`.
- **Rules file:** remove exactly the `## Knowledge base (avista-kb plugin)` section, from its heading
  to the next `## ` heading, and nothing else.

Confirm in one line: `Done: handoffs are now <kept local / pushed / pushed with a pull request>.`

**Choosing "Push…" here is the user's standing permission** for `kb-handoff` to push that branch, and
open the pull request, after every handoff. It never covers merging, and never pushes `main`.

## Step 3: do it

**Clone**, when `kb_path=none`:

```bash
gh repo clone Avista/avista-knowledge-base "<dir>" \
  || { [ "$ssh_alias" = github.com-avista ] && git clone git@github.com-avista:Avista/avista-knowledge-base.git "<dir>"; }
"$KB" where --set "<dir>"
```

`gh repo clone` uses whichever SSH key answers for `github.com`. On Macs with two GitHub accounts that
can be the personal one, which can't see the repo; the `github.com-avista` alias fallback covers that.
If both fail, show the error and stop.

**Existing clone:** `"$KB" where --set <kb_path>` so the location is saved even if it was found by
fallback. If `kb_dirty=no` and `kb_branch=main`, run `"$KB" sync`. Otherwise leave it, and say in one
line that it's on `<branch>` with local changes.

**Sharing:** `"$KB" config share pr|push|local`.

**Rules file:** append `references/claude-md-section.md` to `~/.claude/CLAUDE.md`, with a blank line before
it. Create the file if it doesn't exist. Never edit other sections.

**Mark done:** `"$KB" config setup done && "$KB" config snooze --unset`.

## Step 4: check the hooks

The plugin's SessionStart hook writes `~/.claude/avista-kb/hook-last-run` each time it runs, and it ran
at the start of this session if hooks load. From the preflight value:

- **A timestamp from today:** hooks are running. Say so.
- **`never` or an old date:** hooks did not run in this session. Run
  `python3 "${CLAUDE_SKILL_DIR}/../../hooks/kb_hook.py" session-start <<< '{"cwd":"'"$PWD"'"}'` to
  show the script itself works. Then tell the user that this Claude app isn't running plugin hooks, so
  the knowledge base reminders depend on the `~/.claude/CLAUDE.md` section. If they skipped that,
  offer it once more.

## Step 5: report

Three to five lines, plain:
- where the knowledge base is, and that it's up to date;
- how handoffs are shared, and that saying *change how handoffs are shared* switches it any time;
- whether hooks are running, or the rules-file backup is in place;
- how to use it: "Just work as usual. When you start something worth tracking, I'll offer to track it.
  To pick up a colleague's work, say *pick up <feature>*."
