---
name: chess-setup
description: "Set up the Avista chess analysis app on this machine end-to-end — clone the app, ask for the user's chess.com username (lichess optional), install dependencies (Python venv + Stockfish), write their profile, and launch the local dashboard. Use when the user says set up chess, install the chess analyzer, analyze my chess games, set up Avista-Chess, get the chess dashboard, onboard the chess plugin, or right after installing the avista-chess plugin. This is the first skill to run; the others (chess-analyze, chess-coach-answer, chess-dashboard) assume the app is already set up."
---

# Set up the Avista chess analysis app

Onboard a user from nothing to a running local chess dashboard analyzing their own
games. **Propose before executing** every step that clones, installs, or runs —
show what you're about to do, get a yes, then do it.

App source (private Avista repo, SSH): `git@github.com:Avista/Avista-Chess.git`

## When to invoke

- Right after the user installs the `avista-chess` plugin.
- "Set up chess", "analyze my chess games", "install the chess analyzer".

Do not use for re-running analysis on an already-set-up checkout — that's
`chess-analyze`. If the target folder already contains the app, offer to just
update the profile / launch instead of re-cloning.

## Workflow

### Step 1 — Preconditions

Check and report, before touching anything:
- `git`, `python3` (3.9+), and `curl` are available.
- **Stockfish**: `command -v stockfish`. If missing, note it — you'll install it in
  Step 5 (macOS) or give instructions (other OS). Don't fail yet.
- **SSH access to the Avista org**: the repo is private. The Avista
  `setup-dev-machine` skill configures multi-account SSH; if `git ls-remote
  git@github.com:Avista/Avista-Chess.git` fails, stop and route the user there
  (or, for non-Avista users, ask them to use an HTTPS URL / get repo access).

### Step 2 — Ask for the profile

Use AskUserQuestion (or plain prompts):
- **chess.com username** — required for most users. (If they only play lichess,
  they can leave it blank and give a lichess username instead.)
- **lichess username** — optional; make "skip" obvious ("most people only have
  chess.com").
- Optionally, how many recent games per platform (default 300).

At least one username is required.

### Step 3 — Validate the usernames (fail fast on typos)

Before cloning, confirm the accounts exist:
- chess.com: lowercase the username and send a User-Agent:
  `curl -fsS -H "User-Agent: avista-chess-setup (<contact-or-generic-email>)" "https://api.chess.com/pub/player/<lowercased>"` — confirm it returns a profile; show the `name`/`url` back to the user.
- lichess (if given): `curl -fsS "https://lichess.org/api/user/<username>"`.
If a lookup fails, re-prompt rather than proceeding.

### Step 4 — Choose target folder and clone

Propose a default folder (e.g. `./avista-chess` in the current directory) and
confirm. Then:
```
git clone git@github.com:Avista/Avista-Chess.git <folder>
```
If the folder exists and already holds the app, skip cloning and go to Step 6
(update profile) instead.

### Step 5 — Environment

From inside the folder:
```
python3 -m venv .venv
.venv/bin/pip install --quiet python-chess requests
```
Then Stockfish, if `command -v stockfish` was empty:
- macOS: `brew install stockfish`
- Debian/Ubuntu: `sudo apt-get install stockfish`
- Windows: point them to https://stockfishchess.org/download/ (or `winget install stockfish`)
The app finds Stockfish on `PATH` automatically. If it can't be installed now,
continue — analysis can be re-run later via `chess-analyze`.

### Step 6 — Write the profile

Write `profile.json` at the app root (it's git-ignored) with the collected values:
```json
{ "chesscom": "<username or empty>", "lichess": "<username or empty>", "max_games": 300, "contact_email": "<optional>" }
```
This is the only configuration step — `src/config.py` reads it.

### Step 7 — Run the pipeline (offer; it's the slow part)

Ask whether to analyze now. If yes, run from the folder (each step prints progress):
```
.venv/bin/python src/fetch.py        # download PGNs
.venv/bin/python src/analyze.py      # Stockfish analysis — minutes for hundreds of games
.venv/bin/python src/build_web.py    # build dashboard data
```
Warn that `analyze` is the long step (~2–3s/game). It's resumable, so it's safe to
interrupt and resume. If they'd rather defer, tell them `/chess-analyze` does this
later.

### Step 8 — Launch

```
python3 src/serve.py
```
Print the URL: **http://localhost:8777**. If they want AI coaching's *Ask live*
button, mention they can add `ANTHROPIC_API_KEY` to a project-local `.env` (see the
app README); the *Queue for Claude* path works without a key.

### Step 9 — Hand off

Tell them what they have and the other skills: `/chess-analyze` (refresh data),
`/chess-coach-answer` (answer questions they queued in the dashboard),
`/chess-dashboard` (relaunch). Done.
