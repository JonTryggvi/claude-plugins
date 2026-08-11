---
name: setup-plugin-autoupdate
description: Wire GitHub Releases + plugin-update-checker (PUC v5) into an Avista WordPress plugin so installs receive one-click updates from tagged releases. Use when the user says "set up auto-updates", "wire up PUC", "scaffold the autoupdater", "add the release workflow", "make this plugin auto-update", "give this plugin the regluvordur release pipeline", or when adding GitHub-Release-based updates to a new WordPress plugin. Do not use for theme update workflows or for plugins that update through the WordPress.org repository.
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
| `__RELEASE_ASSET_SLUG__` | Slug the versioned asset is built from. The asset itself is `<slug>-v<VER>.zip` — do **not** include a version or a `-release` suffix here | `avista-myplugin` |
| `__MAIN_PLUGIN_FILE__` | Filename (not path) of the main plugin file, used by the workflow's installability assertion | `avista-myplugin.php` |
| `__BUILD_DIR_NAME__` | Top-level folder inside the release zip — must equal the folder the plugin is **installed** under (`dirname(plugin_basename())`), which is NOT necessarily your dev checkout's folder | `avista-myplugin` |

Heuristics:

- `__PLUGIN_PASCAL__` should match any class prefix the plugin already uses (search the codebase). If the plugin is fresh, derive it from the plugin name in PascalCase with underscores.
- `__PLUGIN_CONST__` is `__PLUGIN_PASCAL__` uppercased with underscores preserved. If the plugin already defines constants with another prefix, use that prefix instead.
- `__GH_OWNER__` and `__GH_REPO__` come from the git remote URL.
- `__RELEASE_ASSET_SLUG__` should be lowercase-kebab, and normally equals `__BUILD_DIR_NAME__`. The release asset is **versioned** — `<slug>-v<VER>.zip`, e.g. `avista-myplugin-v1.4.18.zip` — so the slug carries no version and no `-release` suffix. Versioned naming is what `~/.claude/CLAUDE.md` documents, it matches `Avista/Avista-Commerce-MyAccount`, and it makes the releases list self-describing.
- `__MAIN_PLUGIN_FILE__` is just the filename of the main plugin file (`avista-myplugin.php`), not a path and not the WP slug — `__PLUGIN_SLUG__` is often PascalCase (`Avista-MyPlugin`) and would not match the real filename.
- `__BUILD_DIR_NAME__` is the folder the plugin lives in **when installed** (e.g. `avista-myplugin`) — this is what determines where the zip unpacks. It is NOT always your local checkout's folder name: a repo cloned as `myplugin/` may be installed on production as `avista-myplugin/`. Get the real value from an installed site — the directory portion of the `active_plugins` entry, i.e. `dirname(plugin_basename(__FILE__))`. **Why it matters:** if it mismatches the install folder, PUC's *admin* update still self-corrects (`UpdateChecker::fixDirectoryName` renames the extracted dir to the live folder during an update), but `wp plugin install <zip> --force` honours the zip's folder name and will unpack a *second, stray* copy under the wrong name instead of upgrading in place.

**If the plugin already ships releases under the old static name** (`avista-<plugin>-release.zip`), do not just switch it: `REQUIRE_RELEASE_ASSETS` fails closed against the regex compiled into the *installed* version, so existing sites would silently stop seeing updates. See `references/conventions.md` → "Fail closed cuts both ways" for the dual-upload migration.

### Step 3 — Confirm

Show the user the placeholder table and ask: "Look right? I'll write the files once you confirm."

Do not skip this. Hardcoding the wrong class prefix or GitHub repo into the bootstrap is annoying to undo because the constants thread through the whole class.

### Step 4 — Write the files

Once confirmed:

1. **Bootstrap class.** Read `references/update-checker-class.php` from this skill's bundle, perform the placeholder substitutions, and write the result either (a) as a new section inside the plugin's main file just after the header constants, or (b) as a standalone `includes/class-update-checker.php` file with a `require_once` from the main file. The regluvordur convention is option (a) — inline in the main file. Match that unless the user prefers otherwise.

2. **Workflow YAML.** Read `references/release-workflow.yml`, substitute placeholders, and write to `.github/workflows/release.yml`. Create the `.github/workflows/` directory if needed.

   **Do not write this file through the GitHub REST contents API.** That path requires the `workflow` token scope; the Avista org account (`jontryggviAvista`) has `repo` but not `workflow`, and the API rejects the write with a misleading **`404`** rather than a `403`. Commit workflow files over git-over-SSH. If you see a 404 writing to `.github/workflows/` on a repo you can otherwise write to, it's the token scope, not the path.

3. **Composer dependency.** Open the plugin's `composer.json` (create one if missing) and add `"yahnis-elsts/plugin-update-checker": "^5.6"` under `require`. This constraint deliberately floats across minors, which is exactly why the bootstrap class must not pin a `v5pN` namespace. If creating from scratch, use a minimal manifest:

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
  4. Commit the changes (the user runs `gsend "Add GitHub-Release auto-updater (PUC v5)"`). Workflow files must go over git-over-SSH, not the REST contents API — see Step 4.2.
  5. Push to `main`.
  6. Create the first release: `gh release create v0.1.0 --title "v0.1.0" --notes "Initial release with auto-updater wired"` (or via the GitHub web UI). Once the release is published, the workflow builds the zip, asserts it contains both the plugin entrypoint and `vendor/autoload.php`, and attaches it as `__RELEASE_ASSET_SLUG__-v0.1.0.zip`.

Then confirm the updater actually registered — this pipeline's characteristic failure is being wired up wrong and saying nothing at all. On an installed site:

```bash
wp eval 'var_dump( class_exists( "\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory" ) );'
```

If that prints `false`, `vendor/` never made it onto the site. If it prints `true` but no update is ever offered, check the asset name on the release against the regex in the bootstrap class — a mismatch fails closed and is silent by design.

Mention the `release-plugin` skill for shipping subsequent versions.

## Conventions

The bootstrap class encodes several non-obvious guards. Each exists for a specific reason — do not strip them when adapting the template. See `references/conventions.md` for the full list with the reasoning behind each one.

**The one rule to not get wrong:** never hardcode a `v5pN` PUC namespace. The Composer constraint `^5.6` floats — it resolves to `v5p7` today — so a pinned `v5p6` reference stops resolving on the next minor. Use the `v5` alias for the factory, and resolve `REQUIRE_RELEASE_ASSETS` off `get_class( $api )` because that constant is not exposed through the alias. Getting the factory wrong disables updates **silently**; getting the constant wrong is a **fatal error**. Both are in `references/conventions.md` → "Never hardcode a `v5pN` namespace".

## Templates bundled

- `references/update-checker-class.php` — the PUC bootstrap class with placeholders.
- `references/release-workflow.yml` — the GitHub Actions workflow.
- `references/conventions.md` — non-obvious guards and their reasoning.
