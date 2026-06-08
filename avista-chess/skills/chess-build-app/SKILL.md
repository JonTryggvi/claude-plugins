---
name: chess-build-app
description: "Build the standalone macOS app (AvistaChess.app) from an already-set-up Avista-Chess checkout, then open it — so it runs on its own with no terminal or Claude Code. Use when the user says build the mac app, make a desktop app, package as a .app, make it a standalone app, build a double-clickable app, or turn the chess tool into an app. macOS only. Assumes chess-setup has already cloned the app and created the venv."
---

# Build the standalone macOS app

Package the Avista-Chess tool into `dist/AvistaChess.app` — a double-clickable app
bundling Python, the dashboard, and Stockfish — and open it. This is the no-terminal,
no–Claude-Code path for non-developer Mac users. **Propose before executing** the
install and build (they take a minute and pull ~250MB of build tooling).

## When to invoke

- "Build the mac app", "make a desktop app", "package as a .app".
- After `chess-setup`, when the user wants a double-clickable app rather than the
  browser/localhost flow.

This is **macOS only** (the bundle uses WKWebView + a macOS Stockfish binary). On
other OSes, stop and explain that the standalone app is mac-only; the browser flow
(`/chess-dashboard`) works everywhere.

## Workflow

1. **Locate the app folder** — the Avista-Chess checkout (contains `build_app.sh`,
   `app.py`, and `.venv/`). Ask if it isn't obvious. If there's no checkout yet,
   route to `chess-setup` first.
2. **Confirm platform** — `uname` must be `Darwin`. If not, stop (see above).
3. **Install the build dependencies** into the project venv (one-time, ~250MB):
   ```
   .venv/bin/pip install pywebview pyinstaller
   ```
   Stockfish must be on PATH (the script bundles its binary) — `command -v stockfish`;
   if missing, `brew install stockfish` first.
4. **Build** (propose, then run — takes ~1 minute):
   ```
   ./build_app.sh
   ```
   It produces `dist/AvistaChess.app`.
5. **Open it**: `open dist/AvistaChess.app`. Tell the user that because it's
   **unsigned**, the *first* launch needs **right-click → Open → Open** to get past
   Gatekeeper; after that a normal double-click works.
6. **Hand off**: the app is self-contained — it keeps its data in
   `~/Library/Application Support/AvistaChess/` and shows a first-run setup screen
   (chess.com username, optional API key) on first launch. They can move
   `AvistaChess.app` to /Applications or hand the folder to someone else on an
   Apple-Silicon Mac. For wider/clean distribution (no right-click dance), mention
   that signing + notarization with an Apple Developer ID is the next step — see
   `docs/macos-app.md` in the checkout.

Keep the unsigned/GPL/Apple-Silicon caveats honest (they're documented in
`docs/macos-app.md`): fine for internal Avista Macs, more work for public release.
