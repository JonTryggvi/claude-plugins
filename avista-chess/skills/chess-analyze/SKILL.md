---
name: chess-analyze
description: "Refresh the chess analysis data for an already-set-up Avista-Chess checkout — fetch the latest games, run Stockfish analysis, and rebuild the dashboard data. Use when the user says re-analyze my chess games, fetch my latest games, update the chess dashboard, refresh chess analysis, I played new games analyze them, or rebuild the chess data. Assumes chess-setup has already run (the app folder + profile.json + venv exist)."
---

# Refresh chess analysis

Re-run the pipeline on an existing Avista-Chess checkout so the dashboard reflects
newly played games. **Propose before executing** — analysis is the slow step.

## When to invoke

- The user played more games and wants the dashboard updated.
- "Re-analyze", "fetch my latest games", "rebuild the chess data".

If the app isn't set up yet (no folder / no `profile.json`), route to `chess-setup`.

## Workflow

1. **Locate the app folder.** The current directory if it contains `src/serve.py`
   + `profile.json`; otherwise ask where it was set up.
2. **Confirm scope.** Ask which steps to run (default: all three). Re-fetching is
   cheap; re-analysis is the slow part but is incremental (cached per game, so
   only new games are analyzed).
3. **Run**, from the folder, surfacing progress:
   ```
   .venv/bin/python src/fetch.py        # newest games (skips cached months on chess.com)
   .venv/bin/python src/analyze.py      # only un-analyzed games (resumable cache)
   .venv/bin/python src/build_web.py    # rebuild web/data/*.json
   ```
   For a deeper engine pass, mention `src/analyze.py --depth 16` (slower) and
   `src/build_web.py --deepdive "Ruy Lopez:black"` to add an opening deep-dive.
4. **Tell the user to reload** the dashboard (or run `/chess-dashboard` if it isn't
   running) to see the updated numbers.
