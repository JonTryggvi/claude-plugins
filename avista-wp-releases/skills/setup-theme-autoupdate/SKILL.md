---
name: setup-theme-autoupdate
description: Wire GitHub Releases + plugin-update-checker (PUC v5) into an Avista WordPress theme so installs receive one-click updates from tagged releases. Use when the user says "set up theme auto-updates", "wire up PUC for this theme", "scaffold the theme autoupdater", "add the theme release workflow", "make this theme auto-update", or when adding GitHub-Release-based updates to a WordPress theme. Do not use for WordPress plugins — those have their own skill (setup-plugin-autoupdate) with different version sources and PUC arguments.
---

# Set up the theme auto-update pipeline

Wire GitHub Releases + plugin-update-checker into a WordPress theme so installs detect new versions and offer one-click updates from the WP admin. Parallel to `setup-plugin-autoupdate` but with theme-specific divergences: the version is read from `style.css`, PUC is fed `get_stylesheet_directory() . '/functions.php'`, the release zip is named `{theme-slug}.zip` (no `-release` suffix), and there's no brand-icon injection (themes use `screenshot.png` for the admin UI).

The skill produces three edits to the target theme:

1. A `{{ThemePascal}}_Theme_UpdateChecker` class added to `functions.php` (bootstrap that registers PUC, sets auth, restricts asset matching).
2. A `.github/workflows/release-theme.yml` that builds a `vendor/`-bundled zip on release publish and attaches it.
3. A Composer `require` for `yahnis-elsts/plugin-update-checker:^5.6`.

## When to invoke

Use this skill when the user is asking to add Avista's auto-update pipeline to a WordPress theme. Do not use it when:

- The target is a WordPress *plugin* — use `setup-plugin-autoupdate` instead.
- The theme will be distributed through WordPress.org (use the .org update mechanism instead).
- The theme already has PUC wired up (suggest `release-theme` if they want to ship a version).
- The theme is a *child theme* with the parent already handling updates.

## Workflow

Execute these steps in order. Pause at the confirmation step before writing.

### Step 1 — Verify the theme's current shape

Read the target theme's `functions.php` and `style.css` and confirm:

- `style.css` has a valid theme header (`Theme Name:`, `Version:`, etc.).
- `functions.php` does *not* already define a `*_Theme_UpdateChecker` class or call `PucFactory::buildUpdateChecker()`. If it does, stop and tell the user the pipeline appears wired already.
- The theme is in a git repo with a GitHub remote.

If any prerequisite is missing, ask the user before continuing.

### Step 2 — Gather the placeholder values

| Placeholder | Meaning | Example |
|---|---|---|
| `__THEME_PASCAL__` | PascalCase prefix for the bootstrap class | `Islandiamagica` |
| `__THEME_CONST__` | UPPERCASE prefix for the BOOT_FLAG constant | `ISLANDIAMAGICA` |
| `__GH_OWNER__` | GitHub owner | `Avista` |
| `__GH_REPO__` | GitHub repository name | `islandiamagica` |
| `__THEME_SLUG__` | Theme folder name (matches the directory under `wp-content/themes/`) | `islandiamagica` |

Heuristics:

- `__THEME_SLUG__` is the theme's directory name, lowercase-kebab. It's also the name of the release zip.
- `__THEME_PASCAL__` derives from the slug by PascalCasing it; if the theme already uses a class prefix elsewhere, match that.
- `__THEME_CONST__` is `__THEME_PASCAL__` uppercased.
- `__GH_OWNER__` and `__GH_REPO__` come from the git remote URL.

### Step 3 — Confirm

Show the placeholder table to the user and ask them to confirm before writing.

### Step 4 — Write the files

1. **Composer dependency.** Open the theme's `composer.json` (create one if missing) and add `"yahnis-elsts/plugin-update-checker": "^5.6"` under `require`. Minimal manifest if creating:

   ```json
   {
     "name": "avista/__THEME_SLUG__",
     "description": "<from style.css Description>",
     "type": "wordpress-theme",
     "require": {
       "php": ">=8.0",
       "yahnis-elsts/plugin-update-checker": "^5.6"
     }
   }
   ```

2. **Autoloader guard at the top of `functions.php`.** Just below the opening `<?php` and any existing `if ( ! defined( 'ABSPATH' ) ) exit;` line:

   ```php
   if ( file_exists( __DIR__ . '/vendor/autoload.php' ) ) {
     require_once __DIR__ . '/vendor/autoload.php';
   }
   ```

3. **Bootstrap class.** Read `references/update-checker-class.php` from this skill's bundle, perform placeholder substitutions, and append to `functions.php` after the autoloader.

4. **Workflow YAML.** Read `references/release-workflow.yml`, substitute placeholders, write to `.github/workflows/release-theme.yml`. Note the filename: `release-theme.yml`, not `release.yml`, in case the same repo ever houses both a plugin and a theme.

5. **`.gitignore`.** Ensure `vendor/` is excluded. If the theme has no `.gitignore`, create one with `vendor/` and `.DS_Store`.

### Step 5 — Wrap up

Report files created and the manual next steps:

1. Run `composer install` locally so PUC resolves during dev.
2. Optionally add `define( 'GITHUB_TOKEN', 'ghp_...' );` to `wp-config.php` for the rate-limit raise (60 → 5000 req/hr).
3. The user runs `gsend "Add GitHub-Release auto-updater (PUC v5)"` to commit and push. Workflow files must be committed over git-over-SSH — writing `.github/workflows/` through the GitHub REST contents API needs the `workflow` token scope, which the Avista org account lacks, and the API returns a misleading `404` rather than a `403`.
4. Create the first release: `gh release create v0.1.0 --title "v0.1.0" --notes "Initial release with auto-updater wired"`. Actions builds the zip and attaches it as `__THEME_SLUG__.zip`.

Mention the `release-theme` skill for shipping subsequent versions.

## Conventions

See `references/conventions.md` for the non-obvious guards and reasoning. The plugin and theme versions share most of these — `references/conventions.md` notes the theme-specific divergences.

## Templates bundled

- `references/update-checker-class.php` — the PUC bootstrap class with placeholders.
- `references/release-workflow.yml` — the GitHub Actions workflow.
- `references/conventions.md` — non-obvious guards and reasoning, including what differs from the plugin pattern.
