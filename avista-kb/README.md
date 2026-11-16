# avista-kb

Pick up and hand off work through the Avista knowledge base, a git repo of markdown pages that index
where each feature's code lives, which sites it runs on and what state it is in.

| Skill | What it does |
|---|---|
| `kb-pickup` | Cold-start briefing for a feature or site: where the code is (repo, laptop, server-only), how to reach it, state, next steps, and what the KB is missing. Optionally confirms paths over SSH or `gh`, read-only. |
| `kb-handoff` | End-of-session handoff: updates `handoff.md`, records code locations on site pages, creates the feature from templates if needed, links feature↔site both ways, scans for secrets, commits locally. Never pushes. |
| `avista-kb-overview` | What the KB is and which skill to use. |

`skills/kb-pickup/scripts/kb` is the shared helper (Python 3.9+, standard library only):
`where`, `sync`, `find`, `feature`, `site`, `new-feature`, `link`, `touch`.

Needs a clone of `Avista/avista-kb`. See that repo's README for page conventions.
