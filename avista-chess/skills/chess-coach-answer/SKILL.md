---
name: chess-coach-answer
description: "Answer the coaching questions the user queued from the chess dashboard — read coach.json, find their unanswered questions about specific positions, write back clear, engine-checked coaching, and save it so the answers appear in the dashboard's Coach panel. Use when the user says answer my chess questions, answer my saved coach questions, respond to my queued chess positions, coach my saved positions, or check my chess questions. This is the human-in-the-loop side of the dashboard's 'Queue for Claude' button (no API key needed)."
---

# Answer queued chess coaching questions

The dashboard lets the user queue questions on positions ("Queue for Claude").
They land in `coach.json` as unanswered `user` messages. This skill is you, in the
session, answering them — the free, async coaching loop.

## When to invoke

- "Answer my saved chess questions", "respond to my queued positions".

If `coach.json` doesn't exist or has no unanswered questions, say so.

## Workflow

1. **Find the app folder** (contains `coach.json` at its root). Ask if unsure.
2. **Read `coach.json`.** Its shape is `{ "<key>": { "context": {...}, "messages":
   [ {role, text, mode}, ... ] } }`. A thread needs an answer when its last
   message is a `user` message with no following `assistant` reply.
3. **For each unanswered thread:**
   - Read the `context` (FEN, label, the move the user played, the engine's
     preferred move). The key is `b:<fen>` (blunder trainer) or `g:<game-url>`.
   - **Verify with the engine before claiming anything.** Set up the FEN and run
     Stockfish (the app's venv has python-chess; Stockfish is on PATH) to confirm
     the best move, the line, and *why* the user's move was worse. Do not assert a
     tactic you haven't checked.
   - Write a concise, instructive answer aimed at a club player: name the concrete
     move and the idea, explain the mistake, give a takeaway habit. Plain notation.
4. **Append your answer** to that thread's `messages` as
   `{ "role": "assistant", "text": "..." }` and write `coach.json` back (valid
   JSON). Don't modify other threads.
5. **Tell the user to reload** the dashboard — answers show in the Coach panel on
   each position. Summarize what you answered.

Keep answers honest and specific to the position — this is the whole value of the
async loop over a generic chatbot.
