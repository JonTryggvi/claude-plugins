#!/usr/bin/env bash
#
# prompt-to-body.sh — wrap plain text in an ActiveCollab task-description container.
#
#   prompt-to-body.sh prompt.md                          > body.html
#   prompt-to-body.sh prompt.md "Paste into Claude Code:" > body.html
#   CONTAINER=magic prompt-to-body.sh prompt.md "Prompt:" > body.html
#   CONTAINER=plain prompt-to-body.sh summary.txt         > body.html
#
# Emits HTML for a task's `body` field.
#
#   CONTAINER=code  (default)  <pre data-syntax="markdown"><code>…</code></pre>
#   CONTAINER=magic            the same code block inside ActiveCollab's magic
#                              callout: <aside class="callout-wrapper aside-magic">
#                              <div class="callout-content">…</div></aside>
#   CONTAINER=magic-only       callout with the text as paragraphs, no code
#                              block (loses verbatim whitespace — rarely what
#                              you want for a prompt)
#   CONTAINER=plain            bare escaped paragraphs, no callout and no code
#                              block — for a *record* task, whose description is
#                              a short past-tense note about work already done
#                              rather than a prompt anyone will run
#
# Why this exists: the task body is HTML, so text containing <, > or &
# — shell redirects, comparisons, generics, HTML snippets, file paths — silently
# corrupts the markup if pasted in raw. This escapes them in the right order.
# For prompts, the code block is additionally what makes the text survive
# copy-paste with its whitespace and line breaks intact, so whoever picks the
# task up can paste it straight into Claude Code and start. All of this is
# verified to round-trip through the API with the classes and data-syntax
# attribute preserved.
#
# Always go through this script rather than building the body inline: the shell
# these skills run under uses LC_CTYPE="C", so Icelandic characters in an inline
# argument throw `character not in range`. File in, file out, no multibyte
# character ever becomes an argument.
#
# Compose the payload with jq so the HTML is JSON-escaped properly:
#   prompt-to-body.sh prompt.md "Prompt:" > /tmp/body.html
#   jq -n --arg n "$NAME" --rawfile b /tmp/body.html \
#     '{name:$n, body:$b, assignee_id:6}' > /tmp/payload.json
#   ac POST /projects/479/tasks "$(cat /tmp/payload.json)"
#
set -uo pipefail

PROMPT_FILE="${1:?usage: prompt-to-body.sh <text-file> [intro-text]}"
INTRO="${2-}"
SYNTAX="${SYNTAX:-markdown}"
CONTAINER="${CONTAINER:-code}"

[ -f "$PROMPT_FILE" ] || { echo "prompt-to-body.sh: no such file: $PROMPT_FILE" >&2; exit 66; }
[ -s "$PROMPT_FILE" ] || { echo "prompt-to-body.sh: $PROMPT_FILE is empty" >&2; exit 65; }

case "$CONTAINER" in
  code|magic|magic-only|plain) : ;;
  *) echo "prompt-to-body.sh: CONTAINER must be code, magic, magic-only or plain (got '$CONTAINER')" >&2; exit 64 ;;
esac

# & must be escaped first, or the & in &lt; gets double-escaped.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

emit_intro() {
  [ -n "$INTRO" ] && printf '<p>%s</p>' "$(printf '%s' "$INTRO" | esc)"
  return 0
}

emit_code() {
  printf '<pre data-syntax="%s"><code>' "$SYNTAX"
  esc < "$PROMPT_FILE"
  printf '</code></pre>'
}

# Blank-line-separated blocks become paragraphs; whitespace is NOT preserved.
emit_paragraphs() {
  esc < "$PROMPT_FILE" | awk 'BEGIN{RS="";ORS=""} {gsub(/\n/,"<br>"); print "<p>" $0 "</p>"}'
}

case "$CONTAINER" in
  code)
    emit_intro
    emit_code
    ;;
  magic)
    printf '<aside class="callout-wrapper aside-magic"><div class="callout-content">'
    emit_intro
    emit_code
    printf '</div></aside>'
    ;;
  magic-only)
    printf '<aside class="callout-wrapper aside-magic"><div class="callout-content">'
    emit_intro
    emit_paragraphs
    printf '</div></aside>'
    ;;
  plain)
    emit_intro
    emit_paragraphs
    ;;
esac
