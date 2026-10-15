# Put a static site live: GitHub plus Cloudflare

For static HTML projects (design prototypes, markup handoffs) that need a public URL before they can go
into Clarity. The site deploys as a **Cloudflare Worker with static assets**, the modern equivalent of
Pages for a static site.

Precedents to copy from: [`Avista/LHI-Design`](https://github.com/Avista/LHI-Design) and
[`Avista/Idnu-Design`](https://github.com/Avista/Idnu-Design). Each has static HTML at the root, `Brand/`
for logo assets, and the five files below.

**Confirm with the user before step 2 and step 3.** Creating a repo in the Avista org and deploying to
the shared Cloudflare account are both visible to the whole team.

## The Cloudflare account

**Avista Cloud: DNS & CDN Management**, id `5509a27c3d5b61571543944607792ae7`. Pin it in
`wrangler.jsonc` and in the environment so wrangler never prompts for an account.

## Step 1: add the project files

Use the repo name in the GitHub sense (`Idnu-Design`) and its lowercase-hyphenated form for the worker
(`idnu-design`). Don't overwrite a file that already exists; compare and add what's missing.

**`.gitignore`**

```
# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Editors / IDEs
.vscode/
.idea/
*.swp
*.swo

# Claude Code
.claude/

# wrangler files
.wrangler
.dev.vars*
!.dev.vars.example
.env*
!.env.example
```

**`.assetsignore`**: this one matters. With `assets.directory: "."`, wrangler uploads everything in the
folder, and without this file that includes `.git/`. That publishes the whole repo history, from a
private repo, to anyone who asks for `/.git/HEAD`.

```
**/.DS_Store
.git
.git/**
.claude
.claude/**
.wrangler
.wrangler/**
.gitignore
.assetsignore
.clarity.json
wrangler.jsonc
README.md
node_modules
```

**`wrangler.jsonc`**: `compatibility_date` is today. `account_id` is pinned so deploys skip the account
lookup, which is also what fails first when the cached login expires.

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "<repo-name-lowercase>",
  "account_id": "5509a27c3d5b61571543944607792ae7",
  "compatibility_date": "YYYY-MM-DD",
  "observability": { "enabled": true },
  "assets": { "directory": "." },
  "compatibility_flags": ["nodejs_compat"]
}
```

**`README.md`**: one line of title and one of description.

```
# <RepoName>
<Project> design and markup files
```

**`sitemap.xml`**: relative `<loc>` (no domain, so it works on any host), `<lastmod>` today. Priority
1.0 for the index, 0.7 to 0.9 for key marketing and commerce pages, 0.3 to 0.5 for account and legal.
This file is what `clarity collect --dir .` reads first, so keep it in step with the HTML files.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>/index.html</loc><lastmod>YYYY-MM-DD</lastmod><priority>1.0</priority></url>
  <url><loc>/about.html</loc><lastmod>YYYY-MM-DD</lastmod><priority>0.8</priority></url>
</urlset>
```

## Step 2: create the repo and push

Add explicit paths, so `.DS_Store` and stray files stay out:

```bash
git init -b main
git add .gitignore .assetsignore README.md wrangler.jsonc sitemap.xml Brand *.html
git commit -m "Initial commit: <Project> design and markup files"

gh repo create Avista/<RepoName> --private \
  --description "<Project> design and markup files" \
  --source=. --remote=origin --push
```

If the push fails with `Permission denied (publickey)`, `gh` is set to SSH but this machine has no SSH
key on GitHub. Switch the remote to HTTPS and let `gh` supply the token:

```bash
gh auth setup-git
git remote set-url origin https://github.com/Avista/<RepoName>.git
git push -u origin main
```

## Step 3: deploy

wrangler doesn't need to be installed; `npx` fetches it.

```bash
CLOUDFLARE_ACCOUNT_ID=5509a27c3d5b61571543944607792ae7 npx --yes wrangler@latest deploy
```

The first run on a machine opens a browser for Cloudflare login; the user picks **Avista Cloud: DNS &
CDN Management**. The output ends with the URL:
`https://<repo-name>.avista-cloud-dns-cdn-management.workers.dev`.

## Step 4: verify

All four, every first deploy:

```bash
U=https://<repo-name>.avista-cloud-dns-cdn-management.workers.dev
curl -sS -o /dev/null -w 'index   %{http_code}\n' "$U/index.html"   # 200
curl -sS -o /dev/null -w 'git     %{http_code}\n' "$U/.git/HEAD"    # must be 404
curl -sS -o /dev/null -w 'sitemap %{http_code} %{content_type}\n' "$U/sitemap.xml"  # 200 application/xml
gh repo view Avista/<RepoName> --json url,defaultBranchRef --jq '.url + " on " + .defaultBranchRef.name'
```

If `/.git/HEAD` returns anything but 404, stop and tell the user: `.assetsignore` is missing or wrong,
and the repo is publicly readable until it's fixed and redeployed.

Then go back to the skill and connect the URL to Clarity.

## Redeploy

From the repo root, after changes are committed and pushed:

```bash
CLOUDFLARE_ACCOUNT_ID=5509a27c3d5b61571543944607792ae7 npx --yes wrangler@latest deploy
```

Re-check `index.html` returns 200, then sync pages to Clarity.

If deploy fails with `Failed to automatically retrieve account IDs ... user account fetch permission
denied`, the cached Cloudflare login has expired. The user runs this in their own terminal and picks
the Avista Cloud account in the browser:

```bash
npx wrangler@latest login
```

Then the deploy works again. Claude can't do this step; it needs an interactive browser login.

No CI deploys these sites by default. To deploy on every push instead, it's Cloudflare dashboard →
Workers & Pages → the worker → Settings → Builds → Connect to GitHub.
