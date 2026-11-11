---
name: voice-write
description: Write emails and messages in the user's own voice, using their personal profile at ~/.claude/voice/profile.md. Use whenever drafting, replying to, rewriting or polishing an email, Gmail draft, client reply, status update, Slack/Teams message or ticket comment that the user will send under their own name, even when they only say "svaraðu þessu", "skrifaðu póst", "reply to this", "draft an answer", "make this sound like me", "less stiff", "shorter", or paste an email and ask for a response. Not for company-voice writing (proposals, website copy, marketing) unless the user asks for their own voice. Gmail drafts are then written with gmail-draft.
---

# Write in the user's own voice

The voice comes from one local file, `~/.claude/voice/profile.md`, built from the user's own sent mail by the `voice-profile` skill. Each person has their own profile, on their own machine. This skill holds no voice of its own.

## 1. Load the voice

```bash
test -f ~/.claude/voice/profile.md && head -3 ~/.claude/voice/profile.md
```

- **Profile exists:** read the whole file before writing. Follow it over any general style habits, including the "My own notes" section, which is the user's own correction and wins over everything else in the profile.
- **The user has a hand-written voice skill** (a personal skill whose description says it writes as them): that skill takes precedence. Use the profile only for what the skill doesn't cover.
- **No profile:** don't block. Write the draft now in a plain, direct, professional voice: the answer first, short, no stock openers or closers, matching the thread's language. Then offer once, in one line under the draft, to build a profile with `voice-profile` ("This took about a minute and reads only your own sent mail."). Don't offer again in the same session if they decline.
- **Profile older than about six months** (the `Built:` date on line 3): write with it anyway, and mention once that a refresh would pick up recent changes.

Never read, copy or send the profile anywhere else. It's personal and stays on the user's machine.

## 2. Write the draft

- **Facts come from the thread, the codebase or the user.** Never invent order numbers, times, amounts, names or decisions. Leave a placeholder like `[?]` and list the gaps in one line under the draft.
- **Match the thread's language**, and use the profile's rules for that language.
- **Pick the shape before the words.** Use the profile's length and register section to decide whether this is a one-liner, a short fix report or a structured explanation. When unsure, choose the shorter.
- **Greetings and gendered forms:** use the form the user has used with this person before, found in the thread. Don't guess from a name; use the profile's neutral greeting instead.
- **Humour:** only at the dosage and with the audiences the profile allows. Never about money, contracts, legal, security, lost data, or with an upset reader.
- **Rewriting the user's own text:** keep their structure and wording where it already works, and change only what the profile's "Polish: fix vs keep" section calls for.
- **Plain text body.** No markdown bold or headings in an email. Plain section labels, `-` bullets and numbered points are fine. Leave the title and phone number to their mail signature.

Before handing it over, check: Is the first sentence the answer? Could it be half as long? Does every action have an owner? Is the next step clear? Does it sound like the examples in the profile?

## 3. Deliver it

- **Gmail draft or reply:** write the body to a file in the scratchpad and create the draft with the `gmail-draft` skill's script (`--signature` to append their Gmail signature, `--reply-to <message id>` to thread it). Give the user the draft link.
- **Anything else** (Slack, Teams, ActiveCollab, a pasted reply): give the text in a fenced code block so it copies cleanly.
- **Draft, don't send.** Never send, post or reply on the user's behalf, and don't offer to. The user sends it themselves.

## When the user corrects the voice

If the user says a draft doesn't sound like them ("I'd never say that", "too formal", "I don't use emoji with clients"), fix the draft, then offer to add the correction as one line under `## My own notes` in the profile. Write it there only on a yes. Those notes survive every refresh.
