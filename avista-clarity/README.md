# avista-clarity

Connect Avista projects to [Clarity](https://clarity.avista.is) and push their pages there for client
review. Clarity's own source is [`Avista/Avista-Clarity`](https://github.com/Avista/Avista-Clarity).

## Skills

- **`clarity-connect`**: log in, find or create the Clarity project for a site, link the repo with
  `.clarity.json`, and sync the page list. Deploys static HTML sites to Cloudflare first when they
  aren't live yet.
- **`avista-clarity-overview`**: what the plugin does and how the flow goes.

## Layout

```
skills/
  avista-clarity-overview/SKILL.md
  clarity-connect/
    SKILL.md
    scripts/clarity                     the API client, installed to ~/.claude/bin/clarity
    references/static-site-deploy.md    GitHub + Cloudflare playbook for static sites
```

## The client

`scripts/clarity` is a single Python 3.9+ file with no dependencies beyond `curl`. It talks to the
same owner API the dashboard uses (`/api/projects`, `/api/projects/:id/pages`).

Auth: Clarity only has cookie sessions, from `POST /api/auth/login`. `clarity login` runs in the user's
terminal, reads the password with `getpass` (or from 1Password with `--op`), and stores only the
`clarity_sid` cookie in `~/.claude/.env` as `CLARITY_SESSION` (mode 0600). Every request passes its
arguments to curl through a config on stdin, so neither the password nor the cookie shows up in
`ps`. Sessions last 30 days.

Path rules mirror `apps/worker/src/lib/discover.ts` in Clarity (`normalizePath`, `prettifyPath`,
the skipped extensions), so pages pushed by the client and pages found by Clarity's own discovery
never duplicate each other. If those rules change in Clarity, change them here too.

## Testing against a local Clarity

From an `Avista-Clarity` checkout:

```bash
pnpm wrangler d1 migrations apply avista-clarity --local --persist-to /tmp/clarity-state --config wrangler.toml
cd apps/worker && pnpm wrangler dev --config ../../wrangler.toml --port 8799 \
  --persist-to /tmp/clarity-state --var PUBLIC_BASE_URL:http://localhost:8799
```

Then sign up a throwaway `@avista.is` account at `http://localhost:8799/signup` and run the client with
`CLARITY_URL=http://localhost:8799` and `HOME` pointed at a scratch folder, so your real
`~/.claude/.env` isn't touched.

## Possible follow-up

Personal API tokens in Clarity would replace the monthly login. The client would only need to send an
`Authorization` header instead of the cookie.
