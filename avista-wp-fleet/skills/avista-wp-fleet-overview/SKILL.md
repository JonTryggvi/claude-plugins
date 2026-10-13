---
name: avista-wp-fleet-overview
description: Overview of the avista-wp-fleet plugin — what it is for, what each skill does, what's built and what's planned, and the safety rules. Use when the user asks "what does avista-wp-fleet do", "what's in the fleet plugin", "how do I manage all our sites at once", "how do I roll a plugin out to every site", or right after installing the plugin.
---

# avista-wp-fleet — overview

Manage Avista's ~250 WordPress sites on WPMU DEV as one fleet, instead of one SSH session at a time.
It joins three sources into one site map:

- **WPMU DEV Hub API**: the site list, and in API mode, hosting details and plugins.
- **The Avista CRM** (`crm.avista.is`): which customer each site belongs to.
- **`~/.ssh/config`**: which sites we can reach over SSH.

## Skills

| Skill | Status | What it does |
|---|---|---|
| [`fleet-setup`](../fleet-setup/) | Built | Checks the API key, runs the **API key test**, reads the CRM's customer ↔ site links, maps SSH hosts, writes `~/.claude/avista-wp-fleet/sites.json`. Read-only. |
| `fleet-inventory` | Planned | WP/PHP versions and plugins per site; which of our plugins are installed where. Read-only. |
| `fleet-rollout` | Planned | Install or update one of our plugins across chosen sites: staging, then one canary, then batches. Backup, change and check per site; stops on the first failure. |
| `fleet-drift` | Planned | Scheduled report: outdated plugins, missing standard plugins, sites without a recent backup. |

**Start with `fleet-setup`.** Its API key test decides whether the later skills work through the
API or over SSH.

## Safety rules

- The WPMU DEV API key is account-wide with no scopes. It is never printed, pasted into chat, or
  passed as a process argument.
- Read-only by default. Any write to a site, the Hub or the CRM is shown first and needs explicit
  approval.
- Production changes follow `avista-wp-prod-ops`: back up first, verify after, give a one-line rollback.

## Pairs with

- `setup-site-access` (avista-dev-machine): SSH access to individual sites.
- `release-plugin` (avista-wp-releases): ships a new version that a rollout then pushes out.
- `activecollab-log-time` (avista-activecollab): records a rollout's time against the client.
