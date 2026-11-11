---
name: voice-profile
description: Build or refresh the user's personal writing-voice profile from their own sent Gmail — samples recent sent mail read-only through the Gmail API, strips quoted replies and signatures, and writes ~/.claude/voice/profile.md covering languages, greetings and sign-offs, length, directness, humour, phrases used and avoided, and real (anonymised) examples. Use when the user says "analyse my writing style", "learn my voice", "build my voice profile", "make Claude write like me", "update my voice profile", "refresh my tone", "greindu hvernig ég skrifa", or when voice-write finds no profile and the user accepts building one. Everything stays on the user's machine.
---

# Build a voice profile from the user's own sent mail

The output is one local file, `~/.claude/voice/profile.md`, that `voice-write` loads whenever it drafts something the user will send under their own name. The profile describes **this user's** voice, measured from their mail. It is not a house style and not anyone else's voice.

## Privacy (hard rules)

- **Only the user's own sent mail is read.** The script lists messages with the `SENT` label in the signed-in user's mailbox and drops any message whose From address isn't one of the user's own send-as addresses. It never reads received mail, other people's mailboxes or shared inboxes.
- **Read-only.** The script uses the existing `gmail-draft` sign-in and only `GET`s messages. It sends, labels, deletes and modifies nothing.
- **Raw samples go in a private temp directory** (mode 700, files 600) and are **deleted as soon as the profile is written**, with `sent_sample.py clean <dir>`. Message bodies are never printed to the terminal. Recipient addresses aren't stored, only whether a message went inside the user's own domain or outside it.
- **The profile stays on this machine** in `~/.claude/voice/` (mode 700, file 600). It is never committed to any repository, uploaded, pasted into a shared doc, or attached to a ticket, artifact or message. Don't publish it as an Artifact.
- **Examples in the profile are anonymised.** Replace people's names, company names, emails, phone numbers, kennitölur/IDs, order numbers and amounts with neutral stand-ins (`[Nafn]`, `[Fyrirtæki]`, `[pöntun #]`, `[upphæð]`). Keep the user's own first name in sign-offs.
- The text is analysed in this Claude session only, the same way any email the user pastes in would be. Nothing is sent to any other service.

Tell the user these points in two or three lines before fetching, and go ahead unless they object.

## Before you start

1. **Gmail access.** The script reuses the `gmail-draft` OAuth setup. Check key names only:
   ```bash
   grep -oE '^GMAIL_[A-Z_]+=' ~/.claude/.env
   ```
   All three of `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN` must be there. If not, point the user to "Setup" in the `gmail-draft` skill and stop; don't fall back to the Gmail connector, since its search shows only parts of threads and can't pull a clean sample.
2. **Existing profile.** If `~/.claude/voice/profile.md` exists, this is a refresh: read it first. Everything under its `## My own notes` heading is the user's and must be carried over word for word.
3. **A hand-written voice skill.** If the user already has their own voice skill (a personal skill whose description says it writes as them), say that it will keep taking precedence in `voice-write`, and offer the generated profile as something to compare against rather than a replacement.

## Step 1: count, then fetch

```bash
S="<this skill's base directory>/scripts/sent_sample.py"
python3 -I "$S" fetch --plan-only
```

`--plan-only` prints the request count without calling Gmail. Say the number to the user in one line. The default, 200 messages spread evenly across the newest 1,000 sent, is 12 HTTP requests (1 token refresh, 1 `sendAs`, 2 list pages, 8 batch requests of 25 messages each) and about 1,000 quota units. The Gmail API has no per-call charge, but projects have per-user per-minute caps, so the script paces its batches (about a minute for 200) and backs off and retries on rate-limit replies. Don't raise `--count` above 300. More mail doesn't sharpen the profile and only costs time.

Then fetch into the session scratchpad (or omit `--out-parent` for the system temp dir), with a Bash timeout of at least 300000 ms in case the Gmail sign-in needs renewing:

```bash
python3 -I "$S" fetch --out-parent "<scratchpad>"
```

stdout is JSON with `sample_dir`, `fetched`, `kept`, `by_lang` and `date_range`. The directory holds:

- `samples.txt`: one block per message, `=== #n | date | lang | kind (new/reply/forward) | audience (internal/external/mixed) | words`, then the subject and the text the user typed.
- `summary.json`: counts per language, kind and audience, median and 90th-percentile length per language, and the most common first lines and last two lines (greetings and sign-offs).

If `kept` is under about 60, say so: the profile will be thin. Offer a larger `--pool` so the sample reaches further back.

## Step 2: read and analyse

Read `summary.json`, then all of `samples.txt` (in chunks if it is long). Work out the following, with evidence from the samples, not from assumptions about the user's job or nationality:

- **Languages** and the share of each. When does the user switch language: per recipient, per thread?
- **Length and shape.** The median length and the share of very short replies. When do they write long, and how do they structure it: labels, bullets, numbering?
- **Openings.** Does the first sentence answer, or warm up? Greetings per language and per audience, and when the greeting is left out.
- **Sign-offs.** The exact typed closings and when each is used. Whether the name is typed or left to the signature.
- **Directness.** How they ask, decline, push back, deliver bad news and admit a mistake.
- **Humour and warmth.** Is there any, what form does it take, how often, and with whom? Emoji and emoticons, and which ones.
- **Phrases they use.** Recurring openers, transitions, status lines, closers. Quote them exactly.
- **Phrases they avoid.** Common business-email phrases that never appear in the sample (stock openers, "don't hesitate to reach out", over-apology). Only list a phrase as avoided if it would be common in generic mail and appears zero or almost zero times here.
- **Per-language differences.** Register, greetings, humour and length differ between languages for most people.
- **Mechanics.** Typography (quotes, number and date formats), lists, plain text or formatting, typical typos worth fixing and quirks worth keeping.

**Weigh hand-typed mail most.** If the user has drafted mail with Claude or another assistant, some long, polished messages in the sample may not be in their own voice. Short replies, quick acknowledgements and messages with small typos are unmistakably theirs. Look for a date where the style changes: longer mails, cleaner typing, a different typed sign-off. If you find one, say so in the profile, describe both styles, and treat the earlier hand-typed mail as the voice and the later mail as the polish they accept.

**Closings that are really signatures.** A closing that ends a large share of messages word for word, especially a bilingual one or one with the full name ("Best regards / Kær kveðja" plus the full name), is usually inserted by a mail client, not typed. Record it as a signature, not as a sign-off habit, and don't make `voice-write` type it.

**Personal and sensitive mail.** Sent mail can include family matters, bereavement, health, legal disputes, banks and tax. Use those messages only to judge general register, for example how formal the user is with authorities. Never quote them in examples or phrase lists, and don't mention their subject in the profile.

## Step 3: write the profile

Write `~/.claude/voice/profile.md` with this structure. Keep it to about 150–250 lines. It's a working brief for drafting, not a report.

```markdown
# Voice profile: <user's name>

Built: <YYYY-MM-DD> from <kept> sent messages, <date range>. Languages: <e.g. Icelandic 85%, English 15%>.
Refresh: run the voice-profile skill again. Everything under "My own notes" is kept.

## The voice in five lines
<five numbered rules that most distinguish this person's mail from generic mail>

## Length and register
<measured median and short-reply share; the 3–5 kinds of message they write, each with typical length and shape>

## Openings and greetings
<per language and audience; when there is none>

## Sign-offs
<exact closings per language and when each is used; whether the name is typed>

## Directness
<asking, declining, pushing back, bad news, owning mistakes>

## Humour and warmth
<form, frequency, audience scale, emoji; where it never appears>

## Phrases they use
<exact quotes>

## Phrases they never use
<generic phrases absent from their mail>

## Language differences
<what changes between their languages>

## Polish: fix vs keep
<typos and habits to clean up; quirks that are part of the voice>

## Examples
<6–10 short real excerpts, anonymised, each with a one-line label of the situation and register>

## My own notes
<carried over word for word on refresh; on first build, one line inviting the user to add corrections here>
```

Then lock it down:

```bash
mkdir -p ~/.claude/voice && chmod 700 ~/.claude/voice && chmod 600 ~/.claude/voice/profile.md
```

## Step 4: delete the samples

```bash
python3 -I "$S" clean "<sample_dir>"
```

`clean` deletes only a directory that this script created (it checks the name and a marker file). Confirm the JSON says `deleted`. Do this even if writing the profile failed.

## Step 5: hand it over

Tell the user, in a few lines:

- where the profile is, the sample size and the date range,
- the five-line summary of their voice,
- anything the sample couldn't show (for example, too little English to say much about it),
- that they should read it and correct anything under `## My own notes`, which survives refreshes,
- that the raw samples have been deleted.

Don't paste the whole profile into chat unless they ask. Suggest refreshing every few months, or when their role or main clients change.
