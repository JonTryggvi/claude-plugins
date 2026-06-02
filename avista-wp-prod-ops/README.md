# avista-wp-prod-ops

Tools for operating safely on Avista WordPress sites where the working folder is a near-empty *shell* repo and the real code lives on production, reached over SSH. The dominant case: clients on TempURL-style hosts running WP Code Box 2 (`wpcodebox2`), where business logic is rows in the database rather than files in the theme.

## Skills

| Skill | Purpose |
|---|---|
| [`wp-prod-ssh-ops/`](skills/wp-prod-ssh-ops/) | Inspect-first / backup-before-change workflow for WP-over-SSH projects, with full WP Code Box 2 snippet install/update procedure (clone known-good row → `wp eval-file`), Hummingbird cache-clear, and Breakdance-theme-stub awareness. |
| [`overview/`](skills/overview/) | Prints a summary of this plugin — what it's for, the skill, and the safety preconditions. Run `/avista-wp-prod-ops:overview` or ask "what does this plugin do?". |

## When this plugin gets used

Trigger phrases the skill watches for:

- "the code for this client lives on prod, here's the SSH …"
- "back up the wpcodebox snippets before I change anything"
- "this repo is empty, the real site is at host X over ssh"
- Any mention of WP Code Box / `wpcodebox` snippets, Breakdance pages, or editing a live WP site that has no local checkout.

## Distribution

Released through the Avista org marketplace via [`avista-memory-tools:release-skill-bundle`](../avista-memory-tools/skills/release-skill-bundle/). GitHub-sync path — no tags, no PUC, plain `git push` plus an "Update" click in the admin UI.
