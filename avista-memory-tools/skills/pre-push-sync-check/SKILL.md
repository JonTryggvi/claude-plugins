---
name: pre-push-sync-check
description: Check whether the local git branch is in sync with origin/main before pushing or releasing — fetches the remote, compares HEAD to origin/main, and reports ahead / behind / diverged / in-sync. Use when the user says "am I behind main", "check sync", "is my branch up to date", "check if my branch is in line with main", "pre-push check", "sync check", or before any release/merge where shipping stale code or hitting a non-fast-forward push would be costly.
---

# Pre-push sync check

Verify the local branch is in line with `origin/main` before pushing, merging, or releasing. The check is cheap (one fetch + a few rev-parses), and catches:

- A local `main` that's behind `origin/main` because someone else (or another machine of yours) pushed since your last pull — shipping from this state ships *yesterday's* main.
- A feature branch that was created from a now-stale `main` — merging it later will either fail fast-forward or require a conflict resolution.
- A local branch with unpushed commits you forgot about — useful to surface before a release so they aren't silently bundled in.

## When to invoke

- The user explicitly asks: "am I in sync with main", "check sync", "is my branch up to date", "pre-push check", etc.
- Before any release skill (`release-plugin`, `release-theme`, `release-skill-bundle`) — those skills now run this same check in their pre-flight, but invoking this skill standalone is a quick standalone way to verify without committing to a release.
- Before a `git push` of a long-lived feature branch.
- Before merging a feature branch into `main`, if the user wants to check whether the merge will be a clean fast-forward.

Do not use this skill for:

- Routine commits during active work (you'd run it constantly for no benefit).
- Repos with a different default branch (`master`, `develop`, etc.) without first confirming with the user — the check is hardcoded to `origin/main`.

## Workflow

### Step 1 — Locate the repo

Determine the repo path. If the user is in a session with a project open, default to that project's root. Otherwise ask for the path.

Verify the path is a git repo:

```
git -C <repo-path> rev-parse --is-inside-work-tree
```

If it returns false, stop and tell the user the path isn't a git repo.

### Step 2 — Fetch from origin

```
git -C <repo-path> fetch origin main --quiet
```

This updates `origin/main` to match the remote without touching the working tree or local branches. If the fetch fails (network error, no remote called `origin`, no branch called `main` on the remote), report what failed and stop.

### Step 3 — Read the current branch state

```
git -C <repo-path> rev-parse --abbrev-ref HEAD
git -C <repo-path> rev-parse HEAD
git -C <repo-path> rev-parse origin/main
git -C <repo-path> rev-list --count HEAD..origin/main
git -C <repo-path> rev-list --count origin/main..HEAD
git -C <repo-path> merge-base --is-ancestor origin/main HEAD; echo $?
```

That gives you:

- Current branch name.
- Local HEAD SHA.
- Remote `origin/main` SHA.
- "Behind" count — commits on `origin/main` that aren't reachable from HEAD.
- "Ahead" count — commits on HEAD that aren't on `origin/main`.
- Whether `origin/main` is an ancestor of HEAD (`0` = yes, HEAD is fully up to date with main).

### Step 4 — Classify and report

Four possible states. Report the matching one clearly to the user:

**In sync.** Behind = 0, ahead = 0. HEAD exactly matches `origin/main`.

> Your local branch (`<branch>`) is in sync with `origin/main`. Safe to push or release.

**Ahead only** (typical for a feature branch with unpushed work). Behind = 0, ahead > 0.

> Your local branch (`<branch>`) is ahead of `origin/main` by N commits, with nothing missing from the remote. A `git push` will fast-forward. If you're about to release, confirm those N commits are intended to ship.
>
> List them with: `git log origin/main..HEAD --oneline`

**Behind only** (local out of date). Behind > 0, ahead = 0.

> Your local branch (`<branch>`) is behind `origin/main` by N commits. Pulling won't conflict; run `git pull --rebase` (or `git merge --ff-only origin/main` if on main).
>
> **Do not release or push from this state** — you'd ship stale code or get a non-fast-forward rejection.

**Diverged.** Behind > 0, ahead > 0. Local has commits the remote doesn't, AND the remote has commits the local doesn't.

> Your local branch (`<branch>`) has diverged from `origin/main`: N commits behind, M commits ahead. A direct push will be rejected; a release from this state would ship something that doesn't match either main or your last pull.
>
> Resolve by rebasing onto the latest main: `git fetch && git rebase origin/main`. Or merge: `git merge origin/main`. After resolving, rerun this check.

### Step 5 — Recommend next action

After reporting, give the user a single recommended next command based on the state:

- **In sync** → no action needed; mention they can proceed with the push or release.
- **Ahead only** → `git push` (and a release is safe).
- **Behind only** → `git pull --rebase`.
- **Diverged** → `git fetch && git rebase origin/main`, then rerun the check.

## Notes

- The check is hardcoded to `origin/main`. If the user's default branch is named differently (e.g. `master`, `develop`, `trunk`), the check needs adjustment. Detect via `git symbolic-ref refs/remotes/origin/HEAD` and substitute. Most Avista repos use `main`, so the hardcoded default is fine 99% of the time.
- The fetch in Step 2 is intentionally narrow (`fetch origin main`) — it updates `origin/main` without disturbing other remote-tracking branches. Use this rather than `git fetch --all` to avoid noise.
- If the repo has no remote called `origin`, the skill can't do its job. Report that and stop — don't try to guess an alternative remote name.
- This skill **does not** perform any writes (no pull, no rebase, no merge). It only reads. The user (or a follow-up skill) is responsible for the corrective action.

## Refusal cases

- The path is not a git repo: report and stop.
- No `origin` remote configured: report and stop.
- `origin/main` doesn't exist (the remote has no `main` branch): report and ask the user to confirm the default branch name.
