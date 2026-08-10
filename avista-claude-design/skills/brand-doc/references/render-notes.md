# Render notes — HTML → print-ready PDF

Everything here is a trap that doesn't show up until the PDF is already in someone's inbox. Read it before
writing the HTML, not after the first render looks wrong.

## Contents

1. [Why headless Chrome](#1-why-headless-chrome)
2. [The render command](#2-the-render-command)
3. [Getting the webfont to embed](#3-getting-the-webfont-to-embed)
4. [Print CSS essentials](#4-print-css-essentials)
5. [Embedding the logo](#5-embedding-the-logo)
6. [Token file detection](#6-token-file-detection)
7. [Screen colors vs paper colors](#7-screen-colors-vs-paper-colors)
8. [Verifying the output](#8-verifying-the-output)

---

## 1. Why headless Chrome

reportlab and WeasyPrint don't fetch and subset a Google Font from an `@import`. You get a silent fallback
to a default serif or Helvetica, the PDF renders without error, and it looks *fine* — just not like the
brand. Chrome is a real browser: it resolves the `@import`, downloads the font, embeds a subset, and honours
the same CSS you'd see on screen.

That fidelity is the entire point. If you can't use Chrome, deliver the HTML rather than a
wrong-font PDF (see the fallbacks section of SKILL.md).

## 2. The render command

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
  --virtual-time-budget=4000 --run-all-compositor-stages-before-draw \
  --print-to-pdf="OUT.pdf" "file://ABS/PATH/report.html"
```

| Flag | Why |
|---|---|
| `--no-pdf-header-footer` | Kills Chrome's default page header/footer — the `file://…` URL and print date across the top of a client document. |
| `--virtual-time-budget=4000` | Advances virtual time so network work (the font) completes before print. Without it Chrome prints immediately and the font never arrives. Raise to 8000 for heavy pages. |
| `--run-all-compositor-stages-before-draw` | Waits for layout/paint to settle, so late-applied styles land. |
| `--disable-gpu`, `--no-sandbox` | Standard headless hygiene on macOS. |

The input **must** be an absolute `file://` URL. Relative paths silently produce a blank PDF.

`scripts/render.sh <input.html> <output.pdf>` wraps all of this, finds Chrome across common install paths
(Chrome → Chromium → Edge → Brave, plus `$CHROME_BIN`), and runs the verification in section 8.

## 3. Getting the webfont to embed

Keep the design system's `@import` line **first in the stylesheet** — CSS requires `@import` to precede
other rules, and a misplaced one is dropped without warning.

```css
@import url("https://fonts.googleapis.com/css2?family=Manrope:wght@200..800&display=swap");
```

`display=swap` is right for screen but means Chrome may paint fallback text first. `--virtual-time-budget`
is what saves you — it lets the real font land before the print snapshot. If a render still shows the wrong
face, raise the budget before suspecting the CSS.

Requesting a variable range (`wght@200..800`) matters when the system uses light display weights. Ask only
for the weights you use; a narrower request subsets smaller.

**Offline?** There's no network in some sandboxes. The font then can't embed at all — say so rather than
shipping a fallback-font PDF as if it were branded.

## 4. Print CSS essentials

### Page size and margins

```css
@page {
  size: A4;
  margin: 18mm 16mm 20mm 16mm;
}
```

A4 for Icelandic/EU clients; `Letter` for US. Chrome's default margin is around 1cm and ignores the design
system's spacing scale entirely, so set this explicitly.

### Backgrounds are dropped by default

The single most common surprise. Chrome omits background colors and images when printing unless told
otherwise:

```css
html, body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
```

Without this, every tinted panel, filled callout and inverted header prints white and the layout collapses
into unstyled-looking text.

### Page-break control

```css
h1, h2, h3      { break-after: avoid; }          /* no heading stranded at a page foot */
.card, figure,
table, blockquote { break-inside: avoid; }        /* keep units whole */
.page-break     { break-before: page; }           /* deliberate section breaks */
tr              { break-inside: avoid; }
thead           { display: table-header-group; }  /* repeat headers on long tables */
```

`break-*` is the modern spelling; Chrome still honours `page-break-*`. Include both only if you're
supporting an old engine — otherwise the modern form alone is cleaner.

### Links

Underlines that look right on screen often read as noise on paper, and a URL that can't be clicked is dead
weight. Either style links as plain ink, or expose the target once in a footnote — don't use
`a[href]::after { content: " (" attr(href) ")" }` across a whole document, which shreds line breaks.

## 5. Embedding the logo

Self-contained means no external file references — the PDF is rendered from `file://`, and a missing
relative asset fails silently.

**SVG** — inline the markup directly. Design-system logos commonly use `fill="currentColor"`, which is a
feature: wrap the SVG and set `color` to the ink token, and it recolours with the brand.

```html
<span class="logo" style="color: var(--ink)"><svg viewBox="…">…</svg></span>
```

If the SVG has hardcoded fills instead, set the path's `fill` to `currentColor` yourself to get the same
control. Check for a dark variant (`*_dark.svg`) if you're placing the logo on an inverted surface.

**PNG** — `get_file` returns `isBase64: true` for binaries. Inline the payload:

```html
<img src="data:image/png;base64,iVBORw0KGgo…" alt="Client logo">
```

Give raster logos an explicit `height` and `width:auto`, and remember they won't recolour — on an inverted
header you need a light variant, not a filter.

## 6. Token file detection

Run `list_files` and take the first that exists:

| Order | File | Seen in |
|---|---|---|
| 1 | `styles.css` | Modernist-style systems |
| 2 | `colors_and_type.css` | Avista, RMK |
| 3 | `theme.json` | JSON-token systems |

Assuming a filename is how this breaks — the two systems verified in this org both use
`colors_and_type.css`, which is *not* the first name you'd guess.

Beyond the raw values, mine the token file for:

- **semantic aliases** (`--fg`, `--bg`, `--rule`, `--bg-elev`) — use these over raw palette entries; they're
  the system's intended public API and they're what dark mode remaps
- **comments** — where the system states its actual rules ("One per viewport max", "no pills, no 24px
  cards", "shadows are rare and soft"). These are constraints, not commentary.
- **element styles** below `:root` — many systems style `h1`/`h2`/`p`/`hr` directly, giving you the exact
  weights and tracking to reuse instead of re-deriving them

## 7. Screen colors vs paper colors

A design system's `--paper` is usually an off-white tuned for screens (Avista's is `#EDF2F4`). Flooding an
entire printed page with it wastes ink, prints unevenly on cheap printers, and looks grey rather than
intentional.

Better: set the page to the system's pure white (`--paper-pure`, `#FFFFFF`) and use the tinted `--paper` for
**panels, table header rows and callouts**, where it reads as a deliberate surface. This respects the
system — both colors are its own tokens — while suiting the medium.

Same reasoning for dark mode: never render a document in a system's dark theme unless the user explicitly
asks. It's unreadable when printed and enormous to ink.

## 8. Verifying the output

Two checks, both cheap, catching two different silent failures.

**Content made it:**

```bash
pdftotext OUT.pdf - | head -40
```

Empty or truncated output means the render failed or content is clipped past the page box.

**The font embedded** (needs poppler, same package as `pdftotext`):

```bash
pdffonts OUT.pdf
```

Look for the system's family (e.g. `Manrope`) with `emb = yes`. If you only see `Helvetica` or a base-14
font, the webfont never loaded — raise `--virtual-time-budget`, confirm the `@import` is the first rule, and
check network access before shipping.

If poppler isn't installed, read the PDF directly to confirm it looks right. Don't skip verification
entirely: a wrong-font PDF is indistinguishable from a correct one in a file listing, and the person who
notices is usually the client.
