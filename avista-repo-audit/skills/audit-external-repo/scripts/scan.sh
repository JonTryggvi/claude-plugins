#!/usr/bin/env bash
#
# scan.sh — read-only supply-chain / prompt-injection scanner for an UNTRUSTED
# repository. Emits structured, greppable findings that the audit-external-repo
# skill interprets and risk-scores. It NEVER executes, sources, installs, or
# imports anything from the target — it only reads bytes with find/grep/git-log.
#
#   Usage:  scan.sh <target-dir>
#   Env:    SCAN_MAX=<n>   max match lines shown per probe (default 40)
#
# Output is organised by audit phase. Each probe prints one line:
#     [N] <label>            ← N = number of matches (0 = clean)
# followed by up to SCAN_MAX matching "path:line: text" lines, indented.
# A FLAG TALLY at the end sums the hits for a provisional signal — it is NOT a
# verdict. The human/agent reading this decides the risk level; a benign repo
# will still light up a few probes (documented curl, a legit postinstall, etc.).
#
# Portable to macOS's stock bash 3.2 and to GNU bash/grep. ERE only (no PCRE).

set -u

TARGET="${1:-}"
CAP="${SCAN_MAX:-40}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  echo "usage: scan.sh <target-dir>   (target must be an existing directory)" >&2
  exit 2
fi

cd "$TARGET" || { echo "cannot cd into target: $TARGET" >&2; exit 2; }
TARGET_ABS="$(pwd)"

# Directories excluded from the noisy CONTENT probes to keep signal high. Their
# mere presence (committed deps) is flagged separately in Phase 1 — if they are
# present, re-run with SCAN_MAX high and inspect them directly, as a payload can
# hide inside a committed node_modules/vendor tree.
EXCL=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build \
      --exclude-dir=__pycache__ --exclude-dir=.next --exclude-dir=.svn)

FLAGS=0

hr()  { printf '\n========================================================================\n'; }
sec() { hr; printf '%s\n' "$1"; printf -- '------------------------------------------------------------------------\n'; }

# _emit <label> <grep-output>  — shared formatter; adds match count to FLAGS.
_emit() {
  local label="$1" out="$2" n=0
  [ -n "$out" ] && n="$(printf '%s\n' "$out" | grep -c . )"
  if [ "$n" -gt 0 ]; then
    printf '  [%s] %s\n' "$n" "$label"
    printf '%s\n' "$out" | head -n "$CAP" | sed 's/^/        /'
    [ "$n" -gt "$CAP" ] && printf '        ... (%s more match(es) truncated; raise SCAN_MAX)\n' "$((n - CAP))"
    FLAGS=$((FLAGS + n))
  else
    printf '  [0] %s\n' "$label"
  fi
}

# probe <label> <ERE-regex>  — count + show content matches across the whole tree.
probe() {
  _emit "$1" "$(grep -rniIE "${EXCL[@]}" -- "$2" . 2>/dev/null || true)"
}

# probe_files <label> <ERE-regex> <glob...>  — same, but scoped to matching
# filenames only (kills cross-file noise, e.g. dependency specs live in manifests).
probe_files() {
  local label="$1" regex="$2"; shift 2
  local inc=() g
  for g in "$@"; do inc+=(--include="$g"); done
  _emit "$label" "$(grep -rniIE "${EXCL[@]}" "${inc[@]}" -- "$regex" . 2>/dev/null || true)"
}

# exists <label> <glob-ish path test> — report presence of a file/dir of interest.
present() {
  local label="$1"; shift
  local found=""
  for p in "$@"; do
    [ -e "$p" ] && found="$found $p"
  done
  if [ -n "$found" ]; then
    printf '  [!] %s:%s\n' "$label" "$found"
  else
    printf '  [ ] %s: none\n' "$label"
  fi
}

printf 'REPO AUDIT SCAN (read-only) — no target code was executed\n'
printf 'target : %s\n' "$TARGET_ABS"
printf 'date   : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo 'n/a')"
printf 'scanner: scan.sh (SCAN_MAX=%s)\n' "$CAP"

# ===========================================================================
sec "PHASE 1 — STRUCTURE & METADATA"
# ===========================================================================
printf '\n-- directory tree (depth 3, .git/node_modules/vendor pruned) --\n'
find . -maxdepth 3 \
  \( -name .git -o -name node_modules -o -name vendor -o -name .venv \) -prune -o \
  -print 2>/dev/null | sed 's|^\./||' | sort | head -n 200

printf '\n-- file count by extension (top 30) --\n'
find . -type f -not -path './.git/*' 2>/dev/null \
  | sed -e 's|.*/||' -e 's|^[^.]*$|(noext)|' -e 's|.*\.|.|' \
  | sort | uniq -c | sort -rn | head -30

printf '\n-- git history / maturity --\n'
if [ -d .git ]; then
  printf '   commits    : %s\n' "$(git rev-list --count HEAD 2>/dev/null || echo '?')"
  printf '   first commit: %s\n' "$(git log --reverse --format='%ci' 2>/dev/null | head -1)"
  printf '   last commit : %s\n' "$(git log -1 --format='%ci' 2>/dev/null)"
  printf '   contributors:\n'
  git shortlog -sne HEAD 2>/dev/null | head -10 | sed 's/^/       /'
  printf '   remotes     :\n'
  git remote -v 2>/dev/null | sed 's/^/       /'
else
  printf '   (no .git — local path, not a clone; maturity signals unavailable)\n'
fi

printf '\n-- .gitignore (what is being hidden?) --\n'
[ -f .gitignore ] && sed 's/^/   /' .gitignore | head -60 || printf '   (none)\n'

printf '\n-- setup / entry-point files present --\n'
present "shell setup"     setup.sh install.sh bootstrap.sh init.sh configure run.sh
present "make/task"       Makefile makefile Taskfile.yml justfile
present "python setup"    setup.py setup.cfg pyproject.toml __init__.py conftest.py
present "node setup"      package.json bootstrap.js install.js postinstall.js
present "container/ci"    Dockerfile docker-compose.yml .github/workflows
present "committed deps (payloads can hide here — inspect if present)" node_modules vendor dist build .yarn/cache
present "submodules"      .gitmodules
present "agent tooling (may target the auditing agent — READ manually)" .claude-plugin .claude .mcp.json .cursor .cursorrules .continue AGENTS.md CLAUDE.md .github/copilot-instructions.md

printf '\n-- symlinks (can point outside the repo) --\n'
find . -type l -not -path './.git/*' 2>/dev/null | sed 's|^\./||;s/^/   /' | head -30 || true

# ===========================================================================
sec "PHASE 2 — DEPENDENCY CHAIN & INSTALL HOOKS  (auto-run on install)"
# ===========================================================================
probe "npm lifecycle hooks (preinstall/postinstall/prepare/prepublish)" \
      '"(pre|post)?install"[[:space:]]*:|"prepare"[[:space:]]*:|"prepublish[a-z]*"[[:space:]]*:'
probe_files "floating / unpinned or off-registry dep versions (^ ~ * latest, git+, github:, tarball)" \
      '"[^"]+"[[:space:]]*:[[:space:]]*"(\^|~|\*|latest|[0-9]+\.x|git\+|git:|github:|file:|https?://[^"]+\.(tgz|tar\.gz|zip))' \
      package.json package-lock.json composer.json Gemfile Pipfile pyproject.toml
probe "python install-time hooks (cmdclass/custom install/console entry points)" \
      'cmdclass|class .*install.*\(|console_scripts|entry_points|\[build_system\]|setup_requires'
probe "composer / ruby / rust / go build hooks" \
      '"scripts"[[:space:]]*:|post-install-cmd|post-autoload-dump|Rakefile|build\.rs|go:generate|//go:generate'
probe "Claude/agent plugin auto-run vectors (hooks / mcpServers / commands)" \
      '"hooks"[[:space:]]*:|"mcpServers"[[:space:]]*:|"command"[[:space:]]*:|PreToolUse|PostToolUse|SessionStart'

# ===========================================================================
sec "PHASE 3 — NETWORK & DNS  (payload delivery / exfiltration channels)"
# ===========================================================================
probe "DNS lookups (dig/nslookup/host/getent) incl. TXT-record fetch" \
      '\b(dig|nslookup)\b|\bhost[[:space:]]+-t\b|getent[[:space:]]+hosts|\+short|-type=txt|IN[[:space:]]+TXT'
probe "curl / wget invocations" \
      '\b(curl|wget)\b'
probe "hardcoded IPv4 literals (bypass domain blocking — check context)" \
      '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)'
probe "raw TCP/UDP sockets & reverse-shell primitives (/dev/tcp, nc, socat)" \
      '/dev/(tcp|udp)/|\bnc\b[[:space:]]+-|\bncat\b|\bsocat\b|\btelnet\b|bash[[:space:]]+-i'
probe "python network (socket/urllib/requests/http.client/httpx)" \
      '\bimport[[:space:]]+socket|socket\.socket|urllib|\brequests\.|http\.client|\bhttpx\b|urlopen'
probe "node network (http(s)/net/fetch/axios/node-fetch/dns)" \
      "require\\(['\"](https?|net|dns|dgram)['\"]\\)|https?\\.(get|request)\\(|\\bfetch\\(|\\baxios\\b|node-fetch"

# ===========================================================================
sec "PHASE 4 — DYNAMIC / OBFUSCATED EXECUTION"
# ===========================================================================
probe "pipe-to-shell (curl|wget ... | bash/sh/zsh; also 'sh -c', source <(...))" \
      '(curl|wget|fetch)[^|]*\|[[:space:]]*(bash|sh|zsh|python)|\|[[:space:]]*(bash|sh)[[:space:]]*(-s|-)?[[:space:]]*$|\b(bash|sh|zsh)[[:space:]]+-c\b|source[[:space:]]+<\(|\.[[:space:]]+<\('
probe "eval / exec / compile (shell, python, ruby, php)" \
      '\beval\b|\bexec\b|\bexecfile\b|\bcompile\(|\bsystem\(|\bpassthru\(|\bpopen\(|\bproc_open\('
probe "python subprocess / os.system" \
      'subprocess\.(run|call|Popen|check_output)|os\.system|os\.popen|os\.exec'
probe "node child_process / dynamic Function / vm" \
      "child_process|\\.exec(Sync|File)?\\(|\\.spawn(Sync)?\\(|\\bnew[[:space:]]+Function\\(|\\bvm\\.(run|compile)|require\\(['\"]vm['\"]\\)"
probe "js dynamic-code sinks (Function/eval/setTimeout-string)" \
      '\beval\(|\bnew[[:space:]]+Function\(|setTimeout\([[:space:]]*["'"'"']'

# ===========================================================================
sec "PHASE 5 — ENCODING & OBFUSCATION"
# ===========================================================================
probe "base64 encode/decode" \
      '\bbase64\b|b64decode|b64encode|base64_decode|from_?base64|Buffer\.from\([^,]+,[[:space:]]*["'"'"']base64'
probe "atob / btoa / fromCharCode / unescape chains (JS obfuscation)" \
      '\batob\(|\bbtoa\(|fromCharCode|String\.fromCharCode|\bunescape\(|decodeURIComponent\(.*decodeURIComponent'
probe "hex / octal escape runs & xxd/od decoders" \
      '(\\x[0-9a-fA-F]{2}){4,}|(\\[0-7]{3}){4,}|\bxxd\b|\bod[[:space:]]+-|printf[[:space:]]+["'"'"']\\x'
probe "gzip/zlib/marshal/pickle in-memory decode (packed payloads)" \
      '\bgzip\b|\bzlib\.|\bmarshal\.loads|\bpickle\.loads|inflateRaw|gunzipSync'
probe "long base64-ish blobs (>=120 char runs — likely packed data)" \
      '[A-Za-z0-9+/]{120,}={0,2}'
probe "reversed-string / char-join assembly tricks" \
      '\[::-1\]|\.reverse\(\)\.join|rev[[:space:]]*<<<|\bjoin\(["'"'"']["'"'"'],'

# ===========================================================================
sec "PHASE 6 — CREDENTIAL & ENVIRONMENT HANDLING"
# ===========================================================================
probe "reads of sensitive env vars (API keys, cloud, tokens, ssh-agent)" \
      'ANTHROPIC_API_KEY|OPENAI_API_KEY|AWS_(SECRET|ACCESS)_[A-Z_]*KEY|AWS_SESSION_TOKEN|GITHUB_TOKEN|GH_TOKEN|NPM_TOKEN|SSH_AUTH_SOCK|GOOGLE_APPLICATION_CREDENTIALS|SLACK_TOKEN|STRIPE_[A-Z_]*KEY'
probe "credential-file access (~/.aws, ~/.ssh, .npmrc, docker/config, keychain)" \
      '\.aws/credentials|\.ssh/id_|authorized_keys|\.npmrc|\.docker/config\.json|\.netrc|security[[:space:]]+find-(generic|internet)-password|credential\.helper'
probe ".env file read/write" \
      '\.env(\.local|\.production)?\b|dotenv|load_dotenv|readFileSync\([^)]*\.env'
probe "env dumped to stdout/log (echo/print/console.log of environment)" \
      'echo[[:space:]]+\$[A-Z_]+|\bprintenv\b|(^|[[:space:];&|(])env[[:space:]]*$|console\.log\([^)]*process\.env|print\([^)]*os\.environ'
probe "EXFIL SHAPE: a secret-looking var on the same line as an outbound call (either order)" \
      '\$\{?[A-Z_]*(TOKEN|KEY|SECRET|PASS|CRED|AUTH)[A-Z_]*\}?[^\n]*(curl|wget|fetch|https?://|\bnc\b|ncat)|(curl|wget|fetch|https?://)[^\n]*\$\{?[A-Z_]*(TOKEN|KEY|SECRET|PASS|CRED|AUTH)|https?://[^\n]*(process\.env|os\.environ)'

# ===========================================================================
sec "PHASE 7 — PERSISTENCE & FILE-SYSTEM WRITES (outside repo)"
# ===========================================================================
probe "shell rc / profile modification (.bashrc/.zshrc/.profile)" \
      '\.(bashrc|zshrc|bash_profile|zprofile|profile)\b|>>[[:space:]]*[~\$][^\n]*(bashrc|zshrc|profile)'
probe "cron / at scheduling" \
      '\bcrontab\b|/etc/cron|\bat[[:space:]]+now|systemd.*timer|launchctl|LaunchAgents|LaunchDaemons'
probe "ssh authorized_keys / known_hosts writes" \
      'authorized_keys|known_hosts|\.ssh/config'
probe "system/startup persistence (systemd, /etc, sudoers, startup dirs)" \
      'systemctl[[:space:]]+enable|/etc/(systemd|init\.d|rc\.local|sudoers)|/Library/LaunchDaemons|Startup Items|reg[[:space:]]+add.*Run'
probe "chmod +x  (making something executable — often before running it)" \
      'chmod[[:space:]]+([0-7]*[1357][0-7]*|\+x|u\+x|a\+x)'

# ===========================================================================
sec "PHASE 8 — ERROR-RECOVERY LURES & AGENT-DIRECTED INJECTION"
# ===========================================================================
# The Mozilla 0DIN pattern: a benign-looking error tells the agent to run a
# 'recovery' command that is actually the payload trigger.
probe "instruction-to-run lures ('run X to proceed', 'trust', 'safe to run', 'don't read')" \
      'run[[:space:]]+(this[[:space:]]+(command|script))|run[[:space:]]+(the[[:space:]]+following|`?(curl|wget|npm[[:space:]]+install|node|python[0-9]?[[:space:]]+-m|sh|bash))|to[[:space:]]+(proceed|continue|recover)[^\n]*(run|execute)|(it.?s|is)[[:space:]]+(safe|trusted|fine)[[:space:]]+to[[:space:]]+run|just[[:space:]]+(run|paste|execute|trust)|(do[[:space:]]+not|don.?t)[[:space:]]+(read|inspect|review|open)[[:space:]]+(the|this)'
probe "exceptions/errors carrying a command to run (recovery-flow trigger)" \
      '(raise|throw)[^\n]*(RuntimeError|Error)[^\n]*(run|python|npm|-m[[:space:]])|Error:[^\n]*run[[:space:]]'
probe "prompt-injection markers aimed at an AI agent" \
      'ignore[[:space:]]+(all[[:space:]]+)?(previous|above|prior)[[:space:]]+instructions|you[[:space:]]+are[[:space:]]+now|as[[:space:]]+(an[[:space:]]+)?AI|system[[:space:]]+prompt|<[[:space:]]*system|disregard[[:space:]]+(the[[:space:]]+)?(above|previous)|new[[:space:]]+instructions:'
probe "HTML comments inside markdown/docs (can hide agent instructions)" \
      '<!--'

printf '\n-- zero-width / bidirectional-override unicode (invisible injection) --\n'
if command -v perl >/dev/null 2>&1; then
  perl -Mopen=locale -ne '
    if (/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]/) {
      print "        $ARGV:$.: <U+hidden-char found>\n"; $H++;
    }
    END { print "  [".($H||0)."] hidden/bidi unicode chars\n" }
  ' $(grep -rIl "${EXCL[@]}" '' . 2>/dev/null | head -2000) 2>/dev/null || printf '  [?] perl scan skipped (error)\n'
else
  printf '  [?] perl not available — zero-width/bidi unicode NOT scanned. Check manually.\n'
fi

# ===========================================================================
sec "FLAG TALLY  (provisional signal — NOT a verdict)"
# ===========================================================================
printf '  content-probe matches total : %s\n' "$FLAGS"
printf '\n'
printf '  Interpretation guidance:\n'
printf '    - A LOW/benign repo still trips a handful of probes (documented curl,\n'
printf '      one legit postinstall, base64 in a fixture). Volume alone is not guilt.\n'
printf '    - What matters is COMBINATION: a network fetch + decode + exec in the\n'
printf '      same install path is the reverse-shell chain. Read those in context.\n'
printf '    - Zero hits in Phases 3-8 with clean install hooks => likely LOW.\n'
printf '    - Any Phase 4 pipe-to-shell, /dev/tcp, or Phase 6 EXFIL SHAPE hit => treat\n'
printf '      as HIGH until proven benign by reading the surrounding code.\n'
printf '\nSCAN COMPLETE. No target code was executed.\n'
