---
name: avista-mail-overview
description: Overview of the avista-mail plugin — what it's for, what its skill does, setup, and when it kicks in. Use when the user asks "what does avista-mail do", "what's in this plugin", "how do I get started", or right after installing the plugin.
---

# avista-mail — overview

Email for Claude in Avista's Gmail, with links that stay real.

The problem it solves: the Gmail connector's `create_draft`, `update_draft`, `reply` and `forward` rewrite every link into `https://www.google.com/url?q=REAL_URL&source=gmail&ust=…&sa=E` before saving the draft. Recipients get expiring google.com links that look like phishing. No input format gets past it. This plugin writes drafts through the Gmail API instead, which stores them as given.

Present this overview, then hand off to the skill.

## What's in the box

| Skill | What it does | When it kicks in |
|---|---|---|
| `gmail-draft` | Creates, updates and threads replies as Gmail drafts through the Gmail API (`scripts/gmail_draft.py`, standard library only), appends the Gmail signature, and reads the stored draft back to confirm no wrapped links. Never sends. Also ships `scripts/unwrap.py` to clean already-wrapped text. | Any email draft or reply, especially one with a link. |

## Setup

Once per person, about five minutes — see "Setup" in the `gmail-draft` skill: an OAuth Desktop client in Google Cloud (one can be shared by the team), two keys in `~/.claude/.env`, then a one-time `gmail_draft.py auth` sign-in in your own terminal.

## Make it the default

A skill only loads when its description matches. To make every session use it, add to `~/.claude/CLAUDE.md`:

```
- Write Gmail drafts and replies with the gmail-draft skill script, never the connector's create_draft / update_draft / reply / forward (they rewrite every link to google.com/url). Reading with the connector is fine.
```

## More detail

See the plugin [README](../../README.md).
