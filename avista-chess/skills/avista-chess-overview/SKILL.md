---
name: avista-chess-overview
description: Overview of the avista-chess plugin — what it does, what each skill is for, the order to use them in, and the prerequisites. Use when the user asks "what does avista-chess do", "what's in this plugin", "how do I get started with chess", "which chess skill do I run", or right after installing the plugin.
---

# avista-chess — overview

Turn your online chess games into a local analysis dashboard with coaching. The
plugin clones and sets up the **Avista-Chess** app
(`git@github.com:Avista/Avista-Chess.git`), which imports your chess.com / lichess
games, analyzes them with Stockfish, and serves a dashboard: win-rate and
blunder-by-phase charts, opening-results tables, a click-to-solve **blunder
trainer**, **opening deep-dives**, a **review** queue with notes, and **coaching**
(ask about any position — answered live via your own AI key, or queued for a Claude
session to answer for free).

Present this overview, then route the user to the right skill.

## What's in the box

| Skill | What it does |
|---|---|
| `chess-setup` | **Start here.** Clones the app, asks for your chess.com username (lichess optional), installs the Python venv + Stockfish, writes your profile, optionally runs the first analysis, and launches the dashboard. |
| `chess-analyze` | Re-run the pipeline after you've played more games — fetch latest, analyze (incremental/resumable), rebuild dashboard data. |
| `chess-coach-answer` | Answer the questions you queued from the dashboard's *Queue for Claude* button — reads `coach.json`, engine-checks each position, writes coaching back so it appears in the Coach panel. No API key needed. |
| `chess-dashboard` | Relaunch the local dashboard at http://localhost:8777. |
| `chess-build-app` | **macOS only.** Package everything into a double-clickable `AvistaChess.app` (Python + dashboard + Stockfish bundled) that runs with no terminal or Claude Code — for handing to a non-developer. |

## Order

1. `chess-setup` (once) → 2. play chess → 3. `chess-analyze` to refresh →
`chess-dashboard` to view → `chess-coach-answer` whenever you've queued questions.

## Prerequisites

- **Claude Code** on your machine, plus `git`, `python3` (3.9+), and Stockfish
  (setup installs Stockfish via Homebrew on macOS; other OSes get instructions).
- **SSH access to the Avista org** — the app repo is private. If `git` can't reach
  it, run the `setup-dev-machine` skill (in the `avista-dev-machine` plugin) first to configure
  multi-account SSH.
- **Optional:** an `ANTHROPIC_API_KEY` (or other provider key) for live in-dashboard
  coaching; the queue-and-answer-in-Claude path works without one.

## Notes

Your games, analysis, notes, coaching threads, and any API key all stay **on your
machine** — the app runs locally and only calls out to the chess sites' public APIs
(and your AI key, if you use live coaching).
