---
name: fleet-inventory
description: Read every Avista WPMU DEV site's WordPress version, plugins and themes through the Hub API and report where our own plugins run, which versions are in use, and which installs are stale. Use when the user asks "which sites run <plugin>", "what version of Avista Core is out there", "is any v1.x install left", "inventory the fleet", "which sites need updating", "where is <plugin> installed", or before planning a rollout. Read-only.
---

# Fleet inventory

One read-only pass over every site the Hub lists, then a report focused on Avista's own plugins.

```
~/.claude/avista-wp-fleet/
  inventory.json          per site: WP version, plugins (file, version, active, update), themes
  inventory-report.md     our plugins: installs, active count, versions in use
```

**Read-only.** One `GET /sites/{id}` per site. Nothing is installed, updated or activated.

## Hard boundaries

The same key rules as `fleet-setup`: the WPMU DEV key is account-wide with no scopes. Never print it,
never accept it in chat, never pass it as a process argument. The scripts read it from 1Password
(`op://Shared/WPMU DEV API Key/credential`) and pipe it to curl's stdin.

## Step 1 — API key test (required, every run)

Run `fleet-setup`'s API key test first, even if it passed last week. It also refreshes the site list
that this skill walks.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/fleet-setup/scripts/hub-probe.sh"
```

Continue only if `team` is 200 with sites, and `plugins` is 200. If it prints `NO SITES`, or `plugins`
fails, stop and route to `fleet-setup`. This inventory relies on the per-site routes.

## Step 2 — Read every site

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/fleet-inventory/scripts/inventory.sh"
```

About 1.5 seconds per site, sequential (256 sites took 6m19s on 2026-10-19). Run it with a 10-minute
timeout, or in the background for a bigger fleet. A site that returns 429 or 5xx is retried once; a
site that still fails is recorded with its HTTP status, not dropped.

Why `/sites/{id}` and not `/sites/{id}/plugins`: the site response carries the identical plugin list
(verified 2026-10-19, 41 of 41 rows) plus themes and the WP version, so one call does the work of three.

A plugin's `file` is its path, such as `avista-core/avista-core.php`. WPMU DEV's own plugins instead
carry a numeric project id (119 is the Dashboard). Both are stored as strings.

## Step 3 — Refresh the site map, then report

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/fleet-setup/scripts/build-site-map.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/fleet-inventory/scripts/report.sh"
```

`report.sh` takes an optional regex for "our plugins" (default `avista`, case-insensitive):
`report.sh 'avista|regluvordur'`. For one plugin across the fleet, with customer names from the CRM:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/fleet-inventory/scripts/report.sh" --plugin avista-core
```

`--plugin` matches the plugin's folder or its exact name.

## Reading the report

- **Group by folder, not by name.** One plugin often appears under several folders. Installs from a
  GitHub source zip land in `<repo>-main` (for example `Avista-Core-main`, `Avista-Care-Dashboard-main`)
  instead of the plugin's real folder. Point those out. A `-main` folder usually means the install was
  uploaded by hand from a source archive, and it may not receive auto-updates the way a release install
  does. Check that before calling it outdated.
- **"Update available" is the Hub's opinion.** It covers wp.org and WPMU DEV plugins. Our own plugins
  update through GitHub Releases (PUC), which the Hub doesn't know about, so their `has_update` is not
  meaningful. Compare against the latest GitHub release instead.
- **Dashboard status.** Plugin data comes from each site's WPMU DEV Dashboard. A site without an active
  Dashboard has stale or empty plugin data; the report counts those separately.
- **Count projects, not installs**, when sizing work. The same project often has a production site,
  an `*.avista.dev` staging copy and a `.test` or `.local` entry. They are separate Hub sites.

## Reporting to the user

Lead with the answer to the question asked (for example "no v1.x Avista Core is left: all 44 installs
are 2.x"), then the table, then anything odd: off-name folders, inactive installs, very old versions.
Give numbers from this run, with its read time. Don't fix anything from this skill. Updating plugins is
`fleet-rollout`'s job.

## Edge cases

- **The run is interrupted:** re-run it. It writes `inventory.json` only at the end, so a partial run
  never replaces a complete one.
- **A site appears with `ok: false`:** report it with its HTTP status. A 404 usually means the site was
  removed from the Hub after `hub-sites.json` was written; re-run Step 1.
- **The CRM customer column is empty:** the site isn't linked to a customer in the CRM. That's a
  `fleet-setup` gap, not an inventory error.
