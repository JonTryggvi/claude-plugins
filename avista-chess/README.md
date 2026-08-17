# avista-chess

Import your chess.com / lichess games, analyze them with Stockfish, and get a local
dashboard with coaching. The plugin sets up the **Avista-Chess** app
(`git@github.com:Avista/Avista-Chess.git`) for you.

| Skill | What it does |
|---|---|
| `chess-setup` | **Start here.** Clones the app, asks for your chess.com username (lichess optional), installs the Python venv + Stockfish, writes your `profile.json`, optionally runs the first analysis, and launches the dashboard at http://localhost:8777. Propose-before-execute throughout. |
| `chess-analyze` | Re-run the pipeline after playing more games — fetch latest, analyze (incremental & resumable), rebuild dashboard data. |
| `chess-coach-answer` | Answer the questions you queued from the dashboard's *Queue for Claude* button — reads `coach.json`, engine-checks each position, writes coaching back so it shows in the Coach panel. No API key needed. |
| `chess-dashboard` | Relaunch the local dashboard. |
| `chess-build-app` | **macOS only.** Package everything into a double-clickable `AvistaChess.app` (bundles Python + dashboard + Stockfish) that runs with no terminal or Claude Code — for handing to a non-developer. |
| `avista-chess-overview` | Prints what's in the plugin and which skill to run — `/avista-chess-overview`. |

## Why this exists

Both chess.com and lichess have decent built-in review, but neither unifies your
play across the two, and neither explains your *recurring* leaks in plain language
tied to your own games. This app does: it pulls your games from both sites, runs a
consistent Stockfish pass with a blunder methodology that ignores noise (mate-score
caps, "throws" measured as real eval flips, not raw centipawn loss), and surfaces
the patterns — weak openings, the phase where you fall apart, the games you threw
from winning positions — as an interactive dashboard. Coaching is either live
(your own AI key, in the browser) or queued for a Claude Code session to answer for
free.

The plugin exists so a teammate goes from "installed it" to "looking at my own
games" in one `/chess-setup` — clone, prompt for usernames, install deps, analyze,
launch — instead of a manual venv-and-config slog.

## Prerequisites

- Claude Code, plus `git`, `python3` (3.9+), and Stockfish (setup installs it on
  macOS; other OSes get instructions).
- **SSH access to the Avista org** — the app repo is private. Run the
  `setup-dev-machine` skill (in the `avista-dev-machine` plugin) first if `git` can't reach it.
- Optional `ANTHROPIC_API_KEY` (or other provider key) for live in-dashboard
  coaching; the queue path works without one.

## Conventions

- `chess-setup` and the data-refresh skills are **propose-before-execute**: they
  show what they'll clone / install / run and wait for a yes.
- Everything runs **locally** — games, analysis, notes, coaching threads, and any
  API key stay on the user's machine.

## Releasing

Ship new versions through `release-skill-bundle` (bump `plugin.json`, land via the
marketplace flow). The app itself versions separately in its own repo.
