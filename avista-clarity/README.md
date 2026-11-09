# avista-clarity

Connect Avista projects to [Clarity](https://clarity.avista.is) and push their pages there for client
review. Clarity's own source is [`Avista/Avista-Clarity`](https://github.com/Avista/Avista-Clarity).

## Skills

- **`clarity-connect`**: set up a token, find or create the Clarity project for a site, link the repo with
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

Auth, in order of preference (both live in `~/.claude/.env`, mode 0600):

- **`CLARITY_TOKEN`**: a personal API token from Clarity's Users page, sent as
  `Authorization: Bearer <token>`. It doesn't expire. `clarity login --token` reads it with `getpass`
  (or from a 1Password item's `credential` field with `--op`), checks it against `/api/me`, and saves it.
- **`CLARITY_SESSION`**: the 30-day `clarity_sid` cookie from `POST /api/auth/login`. `clarity login`
  reads the password with `getpass` (or from 1Password with `--op`). Used only when no token is set,
  so existing setups keep working.

Either can also be exported in the shell, which overrides the file. Every request passes its
arguments to curl through a config on stdin, so neither the token, the password nor the cookie shows
up in `ps`. Tokens can't be minted with a token (Clarity requires a session for that), and `logout`
can't revoke a token, since Clarity never says which token a request used: revoke it on the Users page.

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

Then sign up a throwaway `@avista.is` account at `http://localhost:8799/signup`, make a token on its
Users page, and run the client with `CLARITY_URL=http://localhost:8799` and `HOME` pointed at a
scratch folder, so your real `~/.claude/.env` isn't touched.
