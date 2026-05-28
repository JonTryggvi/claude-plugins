# avista-wp-releases

Avista's WordPress release pipeline for plugins *and* themes, packaged as a Claude plugin. Four skills, each focused on one concern:

| Skill | What it does |
|---|---|
| `setup-plugin-autoupdate` | Wires GitHub Releases + plugin-update-checker (PUC v5p6) into a new WordPress plugin. Drops in the bootstrap class, the Actions workflow, the Composer dependency, and the conventions. |
| `setup-theme-autoupdate` | Same pipeline for a WordPress theme. Different version source (`style.css`), different PUC arguments (`get_stylesheet_directory()`), different release zip naming (`<theme-slug>.zip`), no brand-icon injection. |
| `release-plugin` | Ships a new version of a plugin that already has the pipeline wired up. Bumps the header version in the main plugin file, prepares the `gsend` commit, walks through creating the GitHub release, verifies the workflow attached `<plugin>-release.zip`. |
| `release-theme` | Ships a new version of a theme. Bumps `style.css`, prepares the `gsend` commit, walks through the release, verifies `<theme-slug>.zip` was attached. |

## Why this exists

Avista ships WordPress plugins and themes to Icelandic clients through a consistent release pattern: bump the version header, push to `main`, cut a GitHub release with a `v*` tag, let GitHub Actions build a `vendor/`-bundled zip and attach it, let PUC on each install detect the new version. That pattern was first wired up by hand in `Avista/Avista-Regluvordur` (plugin) and `Avista/islandiamagica` (theme); this bundle generalizes both so every subsequent project gets the same pipeline as a single skill invocation rather than a copy-paste-and-rename session.

## Conventions baked in

- PUC version pinned to `v5p6` — bump together with the Composer dependency when upgrading.
- Bootstrap class guards `vendor/autoload.php` with `file_exists()` and PUC usage with `class_exists`/`method_exists` so the plugin or theme loads cleanly in dev without `composer install`.
- Release zip matched by a specific regex so PUC ignores GitHub's auto-generated source archives and only picks up the CI-built artifact.
- `vendor/` is git-ignored; only ever compiled by Actions at release time.
- Env-gated `admin_notices` warning for a missing `vendor/` (plugin only; theme variant shows it always).
- Commits use `gsend` (the Avista convention) rather than direct `git commit`.
- The bash sandbox in Cowork sessions does *not* run git — the release skills tell the user to run `gsend` and `gh release create` from their own terminal.

## Plugin vs theme — the seams that matter

| Concern | Plugin | Theme |
|---|---|---|
| Version source | Plugin header (`Version:` in main `.php` file) | `style.css` header |
| PUC `buildUpdateChecker` 2nd arg | `__FILE__` (main plugin file) | `get_stylesheet_directory() . '/functions.php'` |
| Release zip name | `<plugin-slug>-release.zip` | `<theme-slug>.zip` |
| Workflow file | `.github/workflows/release.yml` | `.github/workflows/release-theme.yml` |
| Upload mechanism | `gh release upload --clobber` | `softprops/action-gh-release@v2` |
| Brand icon injection | Yes (icons + banners) | No (uses `screenshot.png`) |
| BOOT_FLAG concern | Defends double-load via mu-plugin + plugins/ | Defends double-load via parent + child theme |

## Installation

Install via Claude's plugin manager — open the `.plugin` file delivered alongside this README and accept.

## Source references

- Plugin pattern lifted from `Avista/Avista-Regluvordur`. See `regluvordur.php` and `.github/workflows/release.yml` for the canonical working implementation.
- Theme pattern lifted from `Avista/islandiamagica` (see `~/.claude/CLAUDE.md` for the documented version of the theme pattern).
