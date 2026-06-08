---
name: chess-dashboard
description: "Launch the local Avista chess dashboard and open it in the browser. Use when the user says open the chess dashboard, launch chess, start the chess app, show my chess analysis, or run the chess server. Assumes chess-setup has already run."
---

# Launch the chess dashboard

Start the local server for an already-set-up Avista-Chess checkout.

## When to invoke

- "Open the chess dashboard", "launch chess", "show my analysis".

If the app isn't set up (no `src/serve.py` / no `web/data/`), route to
`chess-setup`. If it's set up but never analyzed (`web/data/` empty), suggest
`chess-analyze` first.

## Workflow

1. **Locate the app folder** (contains `src/serve.py`). Ask if unsure.
2. **Start the server** from the folder:
   ```
   python3 src/serve.py
   ```
   It serves on **http://localhost:8777** and prints whether an `ANTHROPIC_API_KEY`
   is detected (for the *Ask live* coaching button). Run it in the background so the
   session stays usable, or tell the user it holds the terminal.
3. **Open the URL** for the user and point out the tabs: Dashboard, Blunder
   trainer, Openings, Review, Tools.
4. If `web/data/` is missing or stale, mention `/chess-analyze` to (re)build it.
