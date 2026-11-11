---
name: avista-mail-overview
description: Overview of the avista-mail plugin — what it's for, what its skills do (Gmail drafts with real links, and writing in your own voice), setup, and when each kicks in. Use when the user asks "what does avista-mail do", "what's in this plugin", "how do I get started", or right after installing the plugin.
---

# avista-mail — overview

Email for Claude in Avista's Gmail: drafts with links that stay real, written in your own voice.

The problem it solves: the Gmail connector's `create_draft`, `update_draft`, `reply` and `forward` rewrite every link into `https://www.google.com/url?q=REAL_URL&source=gmail&ust=…&sa=E` before saving the draft. Recipients get expiring google.com links that look like phishing. No input format gets past it. This plugin writes drafts through the Gmail API instead, which stores them as given.

It also learns how *you* write. `voice-profile` reads a sample of your own sent mail and writes a personal profile to `~/.claude/voice/profile.md`; `voice-write` uses it for every email or message you'll send under your name. Each person gets their own profile, built from their own mail, kept on their own machine.

Present this overview, then hand off to the skill that fits.

## What's in the box

| Skill | What it does | When it kicks in |
|---|---|---|
| `gmail-draft` | Creates, updates and threads replies as Gmail drafts through the Gmail API (`scripts/gmail_draft.py`, standard library only), appends the Gmail signature, and reads the stored draft back to confirm no wrapped links. Never sends. Also ships `scripts/unwrap.py` to clean already-wrapped text. | Any email draft or reply, especially one with a link. |
| `voice-profile` | Samples ~200 of your own sent messages read-only (`scripts/sent_sample.py`, batched and paced, about 12 Gmail API requests), strips quotes and signatures, and writes `~/.claude/voice/profile.md`: languages, greetings and sign-offs, length, directness, humour, phrases you use and avoid, and anonymised examples. Deletes the raw samples afterwards. Re-run to refresh; your own notes in the profile are kept. | "Learn my voice", "build my voice profile", "refresh my tone", or when `voice-write` finds no profile. |
| `voice-write` | Loads your profile before drafting or rewriting anything you'll send under your own name, then hands Gmail drafts to `gmail-draft`. With no profile it still writes a plain, direct draft and offers once to build one. | Any reply, email or message you'll send yourself: "svaraðu þessu", "draft a reply", "make this sound like me". |

## Privacy of the voice profile

Only your own sent mail is read, read-only. Raw samples sit in a private temp folder and are deleted once the profile is written. The profile lives in `~/.claude/voice/` (owner-only) and is never committed, uploaded or shared. Examples in it are anonymised. Nobody else's voice ships with the plugin.

## Setup

Once per person, about five minutes — see "Setup" in the `gmail-draft` skill: an OAuth Desktop client in Google Cloud (one can be shared by the team), two keys in `~/.claude/.env`, then a one-time `gmail_draft.py auth` sign-in in your own terminal. `voice-profile` uses the same sign-in, so there's nothing more to set up. Then say "build my voice profile" once.

## Make it the default

A skill only loads when its description matches. To make every session use it, add to `~/.claude/CLAUDE.md`:

```
- Write Gmail drafts and replies with the gmail-draft skill script, never the connector's create_draft / update_draft / reply / forward (they rewrite every link to google.com/url). Reading with the connector is fine.
- When drafting anything I'll send under my own name, use the voice-write skill and my profile at ~/.claude/voice/profile.md.
```

## More detail

See the plugin [README](../../README.md).
