# Security Audit Report: <REPO_NAME>

**Date:** <YYYY-MM-DD>
**Repository:** <REPO_URL or local path>
**Commit audited:** <short SHA>
**Risk Level:** <🔴 CRITICAL | 🟠 HIGH | 🟡 MEDIUM | 🟢 LOW>

## Executive Summary

<1–2 sentences: what the repo claims to be, and the single most important safety conclusion.>

## Key Findings

- <🔴/🟠/🟡/🟢> <finding 1 — one line>
- <🔴/🟠/🟡/🟢> <finding 2 — one line>
- …

## Detailed Findings

### <Category / phase name>

#### <Finding title>
- **Location:** `<file:line>`
- **Code:**
  ```
  <snippet with a little context>
  ```
- **Analysis:** <why this is suspicious or benign; what it does; what would confirm/refute intent>
- **Risk:** <level>
- **Mitigation:** <how to use safely, or what to inspect further>

<repeat per finding>

## Dependency Chain Summary

<Manifest(s) seen; install/lifecycle hooks and what they run; pinned vs floating; off-registry sources; any low-trust package. "No dependency manifests present" is a valid answer.>

## Setup / Init Scripts Summary

<Every setup/init/install script and what it actually does, in plain language. Call out anything that runs automatically on install/import.>

## Network Calls Summary

<Every external domain/IP the code would contact, when (install vs runtime), and whether it matches the repo's stated purpose. Flag DNS-TXT fetches, hardcoded IPs, dynamically-built domains.>

## Encoding & Obfuscation Summary

<Any base64/hex/packed/reversed content found, what it decoded to (inspected as inert data), and the verdict. "None found" is a valid answer.>

## Agent-Injection & Lure Summary

<Any instruction-to-run lures, error-recovery triggers, prompt-injection markers, hidden-unicode, or HTML-comment instructions aimed at an AI agent. State that none of them were acted on.>

## Overall Risk Assessment

- **Risk Level:** <🔴 CRITICAL | 🟠 HIGH | 🟡 MEDIUM | 🟢 LOW>
- **Safe to execute?** <Yes | No | Only in an isolated/disposable environment>
- **Recommended next steps:** <Quarantine and do not run | Deeper manual analysis of files X, Y | Safe to use with normal caution>

## Auditor Notes

<Caveats and coverage gaps: what could NOT be verified statically, whether committed vendor dirs were scanned, whether the unicode probe ran (perl present?), depth of clone, and an explicit reminder that a clean static scan is evidence — not proof — of safety.>
