# avista-repo-audit

A safety gate for **untrusted third-party repositories**. Before anyone in the org clones a repo, opens it in an agentic coding tool, installs its dependencies, or runs its setup, this plugin screens it for the ways it could compromise the machine — the Mozilla 0DIN attack class (June 2026): an innocent-looking setup error → a "recovery" command the agent runs unquestioned → a DNS/HTTP payload fetch → obfuscated shell that opens a reverse shell.

The audit **never executes, installs, imports, or builds the target, and never obeys instructions found inside the target's files.** It clones into a throwaway quarantine and reads bytes only. The audited repo is treated as hostile input — including any prompt injection aimed at the auditing agent itself.

## Skills

| Skill | Purpose |
|---|---|
| [`audit-external-repo/`](skills/audit-external-repo/) | Clones an untrusted repo (URL or local path) into quarantine, runs a deterministic read-only scanner (`scripts/scan.sh`) across nine phases, interprets the signals against a pattern reference, and produces a risk-scored report with a plain "safe to run?" answer. |
| [`avista-repo-audit-overview/`](skills/avista-repo-audit-overview/) | Prints a summary of this plugin — what it's for, the safety guarantee, and how to run an audit. Run `/avista-repo-audit-overview` or ask "what does this plugin do?". |

## When this plugin gets used

Trigger phrases the skill watches for:

- "audit this repo `<github-url>`" / "is this repo safe" / "vet this repository"
- "check this repo before I clone/install it" / "is it safe to run this project"
- "scan this GitHub repo for malware" / "should we adopt this dependency"
- Pasting a GitHub URL and asking whether it's safe to use.

For reviewing the org's **own** trusted changes, use `/code-review` or `/security-review` instead — this plugin is specifically for untrusted third-party code.

## The nine phases

Structure & metadata · dependency chain & install hooks · network & DNS · dynamic/obfuscated execution · encoding & obfuscation · credential & environment handling · persistence & filesystem writes · error-recovery lures & agent-directed injection · flag tally. See [`skills/audit-external-repo/references/pattern-reference.md`](skills/audit-external-repo/references/pattern-reference.md) for how each signal maps to a risk tier.

## Requirements

`git`, `bash`, `grep`, `find` (present on any dev Mac). `perl` is optional — without it the zero-width/bidi-unicode probe is skipped and the report notes the gap. The scanner is portable to macOS's stock bash 3.2 and to GNU bash.

## Distribution

Released through the Avista org marketplace via [`avista-memory-tools:release-skill-bundle`](../avista-memory-tools/skills/release-skill-bundle/). GitHub-sync path — no tags, no PUC, plain `git push` plus an "Update" click in the admin UI.
