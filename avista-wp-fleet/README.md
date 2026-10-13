# avista-wp-fleet

Manage Avista's ~250 WordPress sites on WPMU DEV as one fleet: one site map that knows each site's
Hub id, customer and SSH host, and (planned) staged rollouts of our own plugins across it.

## Status

| Skill | Status |
|---|---|
| `fleet-setup` | Built: API key test, CRM customer ↔ site links, SSH host map, joined `sites.json` |
| `fleet-inventory` | Planned |
| `fleet-rollout` | Planned |
| `fleet-drift` | Planned |

## Prerequisites

- Access to the **WPMU DEV API Key** item in the 1Password **Shared** vault. Every org member with
  that vault gets the key without handling it; `fleet-setup` reads it with `op read` on each run.
  To use a different item, set `WPMUDEV_OP_REF=op://<vault>/<item>/credential` in `~/.claude/.env`.
- The 1Password CLI (`op`) with the app's CLI integration enabled, plus `jq` and `curl`.
- Your own SSH user on the CRM site (`ace-avista.tempurl.host`) and on any client sites you want
  reachable. See `setup-site-access` in avista-dev-machine.

## What we know about the WPMU DEV API (Oct 2026)

- A public Swagger spec is served at `https://wpmudev.com/api/hub/v1/doc` (686 routes). Auth is the
  raw key in an `Authorization` header.
- The key is account-wide with no scopes. Resetting it disconnects every site from the Hub.
- `GET /sites` returns 502, including with the agency's own key (verified 8 Oct 2026). `GET /team`
  returns the full site list (255 sites, but only id, domain and home URL), and per-site routes such as
  `/sites/{id}/plugins` and `/sites/{id}/modules/hosting` work. The hosting module does not expose SSH
  accounts.
- Lists cap at 100 per page with varying defaults; always follow `X-WP-TotalPages`.
- No webhooks. Long operations return an action id to poll.

## Local files

Everything lives in `~/.claude/avista-wp-fleet/` (mode 700, files 600). Nothing is committed.
