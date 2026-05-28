# Avista Claude plugins

Source code for the Claude plugins Avista distributes through its organization marketplace. Each subdirectory is a self-contained plugin — bundle of skills, optional MCP servers, agents, hooks, etc. — with a `.claude-plugin/plugin.json` manifest at its root.

## Layout

| Plugin | Purpose |
|---|---|
| [`avista-wp-releases/`](avista-wp-releases/) | Auto-updater scaffolding and release workflow for Avista WordPress plugins and themes. Four skills covering both surfaces. |
| [`avista-memory-tools/`](avista-memory-tools/) | Maintenance tools for the Claude knowledge layer — CLAUDE.md audit, memory store linter, plugin release workflow. |

## Working in this repo

Each plugin is its own directory tree. To iterate on one:

```bash
cd avista-memory-tools/
# edit skills/<skill-name>/SKILL.md, references/, etc.
# when ready to ship, invoke the release skill in a Cowork or Claude Code session:
#   "release this plugin"
```

The `release-claude-plugin` skill (inside `avista-memory-tools`) handles the version bump, commit, repackage, and walk-through of the marketplace upload UI.

## Conventions

- **Plugin names** are kebab-case, prefixed `avista-` for org clarity. The directory name, the `name:` field in `plugin.json`, and the `name:` field in each `SKILL.md` frontmatter must all match.
- **Skill names** inside a plugin are kebab-case, lowercase alphanumeric + hyphens only, no consecutive hyphens, no leading/trailing hyphens. The SKILL.md `name:` frontmatter must match the parent directory name.
- **Versioning** uses semver in `plugin.json`. Bump on every release. Tags follow `v<plugin-name>-<version>` (e.g. `v-avista-memory-tools-0.2.0`) to disambiguate when multiple plugins ship from the same monorepo.
- **Commits** use conventional format with the plugin as scope: `chore(avista-memory-tools): release v0.2.0`, `feat(avista-wp-releases): add release-theme skill`, etc. Use `gsend` per the Avista global convention rather than direct `git commit`.
- **Build artifacts** (`.plugin` zip files, `dist/`, `build/`) are git-ignored. Regenerate them on demand via the release skill.

## Adding a new plugin

1. Scaffold the directory with the `cowork-plugin-management:create-cowork-plugin` skill in a Cowork session, or copy the structure of an existing plugin and adapt.
2. Place the new plugin as a top-level subdirectory of this repo (`./avista-<name>/`).
3. Add an entry to the Layout table above.
4. Commit with `feat(<plugin-name>): scaffold plugin`.
5. When ready, ship with `release-claude-plugin`.

## Distribution

Plugins are uploaded to the Avista organization marketplace through the Anthropic admin UI. The marketplace handles distribution to all Avista members on their next plugin sync. There is no automated push from this repo to the marketplace — the upload is a manual browser step per release.

## Useful skills for working here

- `avista-memory-tools:release-claude-plugin` — version bump, commit, repackage, upload walkthrough.
- `cowork-plugin-management:create-cowork-plugin` — guided new-plugin scaffolding.
- `cowork-plugin-management:cowork-plugin-customizer` — adapt an existing plugin to evolving conventions.
