---
name: setup-wp-toolchain
description: Install the local WordPress and build toolchain on an Avista Mac — PHP 8 with the extensions WordPress needs, Composer, PHPUnit, wp-cli, Node via nvm, Local by Flywheel plus Docker and mkcert for local sites, and the weasyprint/poppler pair the brand-doc PDF render needs. Use when the user says "set up PHP", "install composer", "set up my WordPress toolchain", "I need wp-cli", "install node", "set up local WordPress development", "composer install fails", "brand-doc can't render a PDF", "PHP is missing an extension", or after dev-machine-doctor reports role tooling missing. Installs by role — nobody needs all of it — and every install is offered, never forced.
---

# Set up the local WordPress toolchain

Installs what's needed to build and test Avista WordPress work locally. Unlike the other setup skills in
this plugin, **this one is role-based: nobody needs all of it.** Ask what the person actually does before
installing anything.

Run `dev-machine-doctor` first — it already reports which of these are present and prints the `brew` line
for each. This skill is the guided version of closing those gaps, with the context the doctor can't fit.

## How to run this (ask first)

Same contract as the rest of the plugin: offer to run the installs or hand over the commands, and remember
the answer. Read-only checks run freely.

**Ask which of these applies before installing:**

| If they… | They need |
|---|---|
| Write or release WordPress plugins/themes | PHP, Composer, PHPUnit |
| Run WordPress sites locally | Local by Flywheel (or Docker), mkcert |
| Work on front-end build steps | Node via nvm |
| Generate client reports with `brand-doc` | weasyprint, poppler |
| Only ever touch production over SSH | **none of this** — wp-cli lives on the server |

That last row matters. A colleague who only does production work over SSH does not need a local PHP at
all, and installing one implies a local workflow they don't have.

## Step 1 — PHP

```bash
brew install php
```

Homebrew's `php` is the current stable major. Verify, and check the extension set WordPress actually
depends on:

```bash
php -v
php -m | tr '\n' ' '
```

The extensions to confirm present — Homebrew's build includes all of them, so this is a check, not a
shopping list:

`mysqli` `pdo_mysql` `gd` `intl` `mbstring` `curl` `zip` `xml` `dom` `simplexml` `exif` `sodium`
`bcmath` `fileinfo` `iconv` `tokenizer` `openssl` `Zend OPcache`

> **Your local PHP will be newer than the client's server.** Homebrew tracks the current major (8.5 at time
> of writing); WPMU DEV sites commonly run 8.1–8.3. Code that runs locally can still break on the server,
> and deprecation notices differ. Before assuming a bug is in the code, check what the server runs:
> `ssh <host> 'php -v'`. Do not "fix" a local-only deprecation in production code without checking.

If someone needs a *specific* older PHP, `brew install php@8.2` and link it per-project rather than
switching the global one — swapping the global PHP breaks every other project on the machine.

## Step 2 — Composer

```bash
brew install composer
```

`composer --version` should report 2.x. Composer 1 is long EOL and cannot resolve the PUC dependency the
release pipeline uses.

> Composer pulls `php` as a dependency, so a machine can have a working `php` without `php` being a
> top-level Homebrew formula. That's fine and not worth "fixing" — `brew list --versions php` confirms
> which version is actually installed either way.

Guarding `vendor/autoload.php` with `file_exists()` is a house rule, not a suggestion — see the WordPress
section of `~/.claude/CLAUDE.md`. A bare `require` takes the whole site down when the folder is missing.

## Step 3 — PHPUnit

```bash
brew install phpunit
```

Only needed by people writing tests. Most Avista WordPress projects don't ship a suite; don't install this
by default.

## Step 4 — wp-cli

```bash
brew install wp-cli
```

**Usually unnecessary locally.** WPMU DEV hosting ships `wp` on the server, and `avista-wp-prod-ops` and
`avista-wp-performance` both invoke it there over SSH (`ssh user@host 'cd <wproot> && wp …'`). Install it
locally only for someone running WordPress on their own machine.

## Step 5 — Node via nvm

`nvm` is already wired into the shell by `setup-dev-machine` (`~/.zsh/env.zsh` sources it). If `nvm` itself
is missing:

```bash
brew install nvm
```

Then install a Node and make it the default:

```bash
nvm install --lts
nvm alias default lts/*
```

Verify with `node -v`. Use a per-project `.nvmrc` (`node -v > .nvmrc`) rather than pinning a global
version, so projects with different Node requirements coexist.

> `nvm` is a **shell function**, not a binary — `command -v nvm` finds nothing even when it works. That's
> expected, not a broken install. Check with `nvm --version` in an interactive shell.

## Step 6 — Local WordPress sites

**Local by Flywheel** is the path of least resistance for a full WP site on the machine — it manages PHP,
MySQL and nginx per site. It's a signed app download, so this is a **browser step they do**:

> Download from `https://localwp.com`, install, and create a site. Local keeps its sites under
> `~/Local Sites/` by default.

**Docker Desktop** is the alternative for projects shipping their own `docker-compose.yml`:

```bash
brew install --cask docker-desktop
brew install docker-compose
```

Docker Desktop must be launched once and left running; the `docker` CLI fails with a socket error
otherwise. That error reads like a broken install and isn't.

**mkcert** gives local sites a browser-trusted certificate, so local HTTPS stops throwing warnings:

```bash
brew install mkcert
mkcert -install          # installs a local CA into the system trust store
```

`mkcert -install` **modifies the system trust store** and will prompt for the account password. Say so
before running it, and let them run it themselves if they'd rather. `mkcert -CAROOT` shows where the CA
lives; `rootCA.pem` and `rootCA-key.pem` in that folder mean it's set up.

## Step 7 — The brand-doc render pair

`avista-design-systems`' `brand-doc` skill renders client reports to print-ready PDF and needs both:

```bash
brew install weasyprint poppler
```

`weasyprint` does the render; `poppler` supplies `pdftoppm`/`pdfinfo` for verifying the result. Missing
either shows up as a render that silently produces nothing useful. Only needed by people producing client
reports.

## Step 8 — Verify

```bash
php -v && composer --version
node -v
command -v wp phpunit weasyprint pdftoppm mkcert docker 2>/dev/null
```

Or just re-run `dev-machine-doctor`, which reports the whole set with install hints for anything still
missing. Report results in plain language and be explicit about what was deliberately skipped — a
colleague should know that "no wp-cli" was a decision, not an oversight.

## Edge cases

- **`brew install` fails on a fresh Apple Silicon Mac** — Homebrew isn't on the PATH yet. That's
  `setup-dev-machine` Part B, not a Homebrew problem.
- **`php` works but a WordPress plugin errors on a missing extension** — check `php -m` against the Step 1
  list. Homebrew's build is complete, so a genuine gap usually means a hand-rolled or system PHP is
  shadowing it; `command -v php` should be under the Homebrew prefix.
- **`docker: Cannot connect to the Docker daemon`** — Docker Desktop isn't running. Launch the app.
- **`nvm: command not found` in a script** — nvm is a shell function and won't exist in a non-interactive
  shell. Source it explicitly, or call the versioned binary under `~/.nvmrc`'s version directly.
- **Local site and a Homebrew MySQL fighting over port 3306** — Local runs its own MySQL per site. Don't
  install a global MySQL unless something specifically needs it.
- **Someone asks for a specific old PHP globally** — install `php@<ver>` alongside and link per project.
  Never downgrade the global PHP to match one client.

## Downstream

With this in place: `setup-plugin-autoupdate` / `setup-theme-autoupdate` and `release-plugin` /
`release-theme` (in `avista-wp-releases`) can scaffold and ship, and `brand-doc` can render. Production
work over SSH needs `setup-site-access` instead — none of this toolchain is required for it.
