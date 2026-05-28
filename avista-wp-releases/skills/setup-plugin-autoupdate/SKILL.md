---
name: setup-plugin-autoupdate
description: Wire GitHub Releases + plugin-update-checker (PUC v5p6) into an Avista WordPress plugin so installs receive one-click updates from tagged releases. Use when the user says "set up auto-updates", "wire up PUC", "scaffold the autoupdater", "add the release workflow", "make this plugin auto-update", "give this plugin the regluvordur release pipeline", or when adding GitHub-Release-based updates to a new WordPress plugin. Do not use for theme update workflows or for plugins that update through the WordPress.org repository.
---

# Set up the auto-update pipeline

Wire GitHub Releases + plugin-update-checker (PUC) into a WordPress plugin so installs detect new versions and offer one-click updates from the WP admin. This is the same pattern used in `Avista/Avista-Regluvordur`, generalized.

The skill produces four edits to the target plugin:

1. A `{{PluginPascal}}_Update_Checker` class added to the main plugin file (bootstrap that registers the PUC checker, sets auth, restricts asset matching, and replaces WP's default icon with the plugin's brand mark).
2. A `.github/workflows/release.yml` that builds a `vendor/`-bundled zip on release publish and attaches it to the release.
3. A Composer `require` for `yahnis-elsts/plugin-update-checker:^5.6`.
4. A version constant derived from the plugin header, and a `.gitignore` entry for `vendor/`.

## When to invoke

Use this skill when the user is asking to add Avista's standard auto-update pipeline to a WordPress plugin. Do not use it when:

- The plugin is going to be distributed through WordPress.org (use the .org update mechanism instead).
- The target is a WordPress *theme* — themes have their own scaffolding (out of scope for this skill).
- The plugin already has PUC wired up (in which case suggest `release-plugin` if they want to ship a version).

## Workflow

Execute these steps in order. Pause at the confirmation step before writing.

### Step 1 — Verify the plugin's current shape

Read the target plugin's main file (`<plugin-folder>/<plugin-slug>.php`) and confirm:

- It has a valid plugin header (`Plugin Name:`, `Version:`, etc.).
- It does *not* already define a `*_Update_Checker` class or call `PucFactory::buildUpdateChecker()`. If it does, stop and tell the user the pipeline appears wired already.
- The plugin is in a git repo with a GitHub remote (`git remote -v` from the plugin folder, or check `composer.json`'s `repository` field). The skill needs the GitHub `owner/repo` to bake into the bootstrap class.

If any prerequisite is missing, ask the user before continuing.

### Step 2 — Gather the placeholder values

From the plugin's existing header, slug, and remote, derive each value below. Show the table to the user and ask them to confirm or adjust before any files are written.

| Placeholder | Meaning | Example |
|---|---|---|
| `__PLUGIN_PASCAL__` | PascalCase prefix for the bootstrap class and constants | `Avista_MyPlugin` |
| `__PLUGIN_CONST__` | UPPERCASE constant prefix matching the plugin's existing constants if any | `AVISTA_MYPLUGIN` |
| `__GH_OWNER__` | GitHub owner | `Avista` |
| `__GH_REPO__` | GitHub repository name | `Avista-MyPlugin` |
| `__PLUGIN_SLUG__` | WP slug used by `plugin_basename()` (often matches `__GH_REPO__`) | `Avista-MyPlugin` |
| `__PLUGIN_TITLE__` | Human-readable plugin name (from the plugin header) | `Avista MyPlugin` |
| `__RELEASE_ZIP_BASE__` | Basename of the release asset, no `.zip` | `avista-myplugin-release` |
| `__BUILD_DIR_NAME__` | Folder name inside the release zip (matches the WP plugin directory name) | `myplugin` |

Heuristics:

- `__PLUGIN_PASCAL__` should match any class prefix the plugin already uses (search the codebase). If the plugin is fresh, derive it from the plugin name in PascalCase with underscores.
- `__PLUGIN_CONST__` is `__PLUGIN_PASCAL__` uppercased with underscores preserved. If the plugin already defines constants with another prefix, use that prefix instead.
- `__GH_OWNER__` and `__GH_REPO__` come from the git remote URL.
- `__RELEASE_ZIP_BASE__` should be lowercase-kebab and include `-release` so it's distinguishable from any other zips the user might attach manually. `avista-<plugin>-release` is the established convention.
- `__BUILD_DIR_NAME__` defaults to the plugin's existing folder name (so the zip extracts to the correct WP plugins folder).

### Step 3 — Confirm

Show the user the placeholder table and ask: "Look right? I'll write the files once you confirm."

Do not skip this. Hardcoding the wrong class prefix or GitHub repo into the bootstrap is annoying to undo because the constants thread through the whole class.

### Step 4 — Write the files

Once confirmed:

1. **Bootstrap class.** Read `references/update-checker-class.php` from this skill's bundle, perform the placeholder substitutions, and write the result either (a) as a new section inside the plugin's main file just after the header constants, or (b) as a standalone `includes/class-update-checker.php` file with a `require_once` from the main file. The regluvordur convention is option (a) — inline in the main file. Match that unless the user prefers otherwise.

2. **Workflow YAML.** Read `references/release-workflow.yml`, substitute placeholders, and write to `.github/workflows/release.yml`. Create the `.github/workflows/` directory if needed.

3. **Composer dependency.** Open the plugin's `composer.json` (create one if missing) and add `"yahnis-elsts/plugin-update-checker": "^5.6"` under `require`. If creating from scratch, use a minimal manifest:

   ```json
   {
     "name": "avista/__GH_REPO__",
     "description": "<copy from plugin header Description>",
     "type": "wordpress-plugin",
     "require": {
       "php": ">=8.0",
       "yahnis-elsts/plugin-update-checker": "^5.6"
     }
   }
   ```

4. **`.gitignore`.** Ensure `vendor/` is excluded. If the plugin has no `.gitignore`, create one with `vendor/` and `.DS_Store`.

5. **Version constant + bootstrap action.** Just below the plugin's existing `define()` constants in the main file, add the version derivation line:

   ```php
   define( '__PLUGIN_CONST___VERSION', (string) ( get_file_data( __FILE__, [ 'Version' => 'Version' ] )['Version'] ?? '0.0.0' ) );
   ```

   And just before the plugin's other `add_action( 'init', ... )` calls, add:

   ```php
   add_action( 'init', [ '__PLUGIN_PASCAL___Update_Checker', 'bootstrap' ], 30 );
   ```

   The `30` is deliberate — late enough that ACF and similar init-time setups have already run.

### Step 5 — Wrap up

After writing, report to the user:

- The files that were created or modified.
- The next manual steps:
  1. Run `composer install` locally so the bootstrap class can find `vendor/autoload.php` during dev.
  2. Add brand assets if desired (`assets/img/icon.svg`, `assets/img/banner.svg`) — the bootstrap class references these but degrades gracefully if missing.
  3. Optionally add `define( 'GITHUB_TOKEN', 'ghp_...' );` to `wp-config.php` to raise the GitHub API rate limit from 60 to 5000 requests/hour for the update checks.
  4. Commit the changes (the user runs `gsend "Add GitHub-Release auto-updater (PUC v5p6)"`).
  5. Push to `main`.
  6. Create the first release: `gh release create v0.1.0 --title "v0.1.0" --notes "Initial release with auto-updater wired"` (or via the GitHub web UI). Once the release is published, the workflow builds the zip and attaches it as `__RELEASE_ZIP_BASE__.zip`.

Mention the `release-plugin` skill for shipping subsequent versions.

## Conventions

The bootstrap class encodes several non-obvious guards. Each exists for a specific reason — do not strip them when adapting the template. See `references/conventions.md` for the full list with the reasoning behind each one.

## Templates bundled

- `references/update-checker-class.php` — the PUC bootstrap class with placeholders.
- `references/release-workflow.yml` — the GitHub Actions workflow.
- `references/conventions.md` — non-obvious guards and their reasoning.
