#!/usr/bin/env bash
#
# prompt-to-body.sh — wrap a plain-text prompt in an ActiveCollab container.
#
#   prompt-to-body.sh prompt.md                          > body.html
#   prompt-to-body.sh prompt.md "Paste into Claude Code:" > body.html
#   CONTAINER=magic prompt-to-body.sh prompt.md "Prompt:" > body.html
#
# Emits HTML for a task's `body` field.
#
#   CONTAINER=code  (default)  <pre data-syntax="markdown"><code>…</code></pre>
#   CONTAINER=magic            the same code block inside ActiveCollab's magic
#                              callout: <aside class="callout-wrapper aside-magic">
#                              <div class="callout-content">…</div></aside>
#   CONTAINER=magic-only       callout with the prompt as paragraphs, no code
#                              block (loses verbatim whitespace — rarely what
#                              you want for a prompt)
#
# Why this exists: the task body is HTML, so a prompt containing <, > or &
# — shell redirects, comparisons, generics, HTML snippets — silently corrupts
# the markup if pasted in raw. This escapes them in the right order. The code
# block is what makes the prompt survive copy-paste with its whitespace and line
# breaks intact, so whoever picks the task up can paste it straight into Claude
# Code and start. All of this is verified to round-trip through the API with the
# classes and data-syntax attribute preserved.
#
# Compose the payload with jq so the HTML is JSON-escaped properly:
#   prompt-to-body.sh prompt.md "Prompt:" > /tmp/body.html
#   jq -n --arg n "$NAME" --rawfile b /tmp/body.html \
#     '{name:$n, body:$b, assignee_id:6}' > /tmp/payload.json
#   ac POST /projects/479/tasks "$(cat /tmp/payload.json)"
#
set -uo pipefail

PROMPT_FILE="${1:?usage: prompt-to-body.sh <prompt-file> [intro-text]}"
INTRO="${2-}"
SYNTAX="${SYNTAX:-markdown}"
CONTAINER="${CONTAINER:-code}"

[ -f "$PROMPT_FILE" ] || { echo "prompt-to-body.sh: no such file: $PROMPT_FILE" >&2; exit 66; }
[ -s "$PROMPT_FILE" ] || { echo "prompt-to-body.sh: $PROMPT_FILE is empty" >&2; exit 65; }

case "$CONTAINER" in
  code|magic|magic-only) : ;;
  *) echo "prompt-to-body.sh: CONTAINER must be code, magic or magic-only (got '$CONTAINER')" >&2; exit 64 ;;
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
    # Blank-line-separated blocks become paragraphs; whitespace is NOT preserved.
    esc < "$PROMPT_FILE" | awk 'BEGIN{RS="";ORS=""} {gsub(/\n/,"<br>"); print "<p>" $0 "</p>"}'
    printf '</div></aside>'
    ;;
esac
