---
name: avista-clarity-overview
description: Overview of the avista-clarity plugin: what it does, the one-time login, and how connecting and pushing a project to Clarity works. Use when the user asks "what does avista-clarity do", "how do I get a site into Clarity", "what's in this plugin", or right after installing it.
---

# avista-clarity

Gets Avista projects into [Clarity](https://clarity.avista.is), our website review tool, and keeps them
current. Clarity points at a live URL, lists the pages reviewers can click through, and gives clients a
share link for pinned comments.

## Skills

| Skill | Use it for |
|---|---|
| `clarity-connect` | Everything: log in, connect a project, push pages. Say "connect this to Clarity" or "push this to Clarity". |
| `avista-clarity-overview` | This page. |

## What happens when you say "connect this to Clarity"

1. **Login check.** Clarity has no API tokens, so the first time (and every 30 days) you run
   `~/.claude/bin/clarity login` in your own terminal. Your password is never stored or shown to
   Claude; only the session lands in `~/.claude/.env`.
2. **Live URL.** Clarity reviews a URL, so the site must be up. A static HTML folder that isn't live
   yet gets a private repo in the Avista GitHub org and a Cloudflare deploy first, after you confirm.
3. **Find or create.** Claude looks for an existing project with the same URL before making one, so
   the team doesn't get duplicates.
4. **Link.** A small `.clarity.json` in the repo records the project id. Commit it and a teammate's
   Claude finds the same project.
5. **Pages.** The page list comes from the folder's HTML and sitemap, or from the live site's sitemap
   for WordPress, including sitemap indexes. Big sites get a choice of which groups to include.

## What "push" does later

Redeploys a static site if there are changes, then syncs pages: new pages are added, pages that came
back are unhidden, and pages that vanished are listed with their comment counts so you can decide.
Nothing is ever deleted, and names you edited in the dashboard are left alone.

## Needs

- An `@avista.is` Clarity account (sign up at <https://clarity.avista.is/signup>).
- `python3`, `curl` and `jq`, which every Avista Mac has.
- For static-site deploys: `gh` logged in to the Avista org, and Node for `npx wrangler`.
