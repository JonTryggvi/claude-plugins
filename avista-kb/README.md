# avista-kb

Track and pick up work through the Avista knowledge base, a git repo of markdown pages that index
where each feature's code lives, which sites it runs on and what state it is in.

## Getting started

Install the plugin from the Avista marketplace. In your next session Claude offers to set it up.
Answer one dialog and Claude clones the knowledge base, configures it and checks it. You can also say
*set up the knowledge base* at any time. After that, just work: Claude offers to track work worth
tracking, and keeps the handoff current.

| Skill | What it does |
|---|---|
| `kb-setup` | One-dialog setup: clone location, how handoffs are shared (pull request, push, or local), and an optional rules-file section. Clones, configures and checks that the hooks run. Re-run it, or say *change how handoffs are shared*, to change a choice. |
| `kb-handoff` | Tracks a feature from the start of the work. One picker offers to track it as a draft, the handoff is updated quietly at each session end and shared as chosen in setup, and a second picker marks it active when finished. Covers repos (plugins, themes, tools) and SSH work on sites. Scans for secrets before committing. |
| `kb-pickup` | Cold-start briefing for a feature, repo or site: where the code is (repo, laptop, server-only), how to reach it, state, next steps, and what the knowledge base is missing. Optionally confirms paths over SSH or `gh`, read-only. |
| `avista-kb-overview` | What the knowledge base is and which skill to use. |

**Hooks** (`hooks/`): at session start in an Avista repo, and on the first SSH to a `*.tempurl.host`
site, they tell Claude whether the knowledge base tracks that work. They also prompt setup on a new
machine. They only add context for Claude and never show anything themselves.

`skills/kb-pickup/scripts/kb` is the shared helper (Python 3.9+, standard library only):
`where`, `config`, `sync`, `find`, `feature`, `site`, `tracked`, `new-feature`, `link`, `status`, `touch`.

The knowledge base itself is `Avista/avista-knowledge-base`. Its README has the page conventions.
