# Browser loop probe: our agent-browser loop on one fixed form task (2026-10-08)

Backlog row `9e97305d19d0` ("SDK browser toolset loop vs our agent-browser loop on one fixed form task").
Source: the 2026-10-07 assessment of the Claude SDK computer-use and browser-use toolsets (§E, "smallest
probe"), and its skeptic pass. Both were session notes under `/tmp` and are summarized here, not linked.

## Verdict

Our loop (Claude Code 2.1.293, `claude-haiku-5-5`, `agent-browser` 0.27.1) entered all three handwritten cards in
every run: median 21 tool calls and 80.6 s, against the launch video's 67 calls and 46 s for the same three cards.
It was not typo-free: 2 of 3 runs typed "Lena Voyt" for card 3's cursive "Lena Vogt", one wrong field out of 27.
Every other field in every run was right.

Against the reading fixed before the runs (zero wrong fields and a median within 138 s closes the question as
"no change"), time passes and accuracy does not, so the question stays open and paying for the SDK arm is the
operator's call. Recommendation: do not pay for it yet, conviction 70%. The one miss is the model reading
cursive, and the SDK loop would run the same model on the same image; what it adds is a crop-and-enlarge `zoom`
tool, and our loop already enlarged card 3 through the page's own zoom before misreading it. The video reports
one run, so "no typos" there is a sample of one.

Cost of our arm, measured: about 260K to 640K cached input tokens per run, 6K to 10K output tokens, and $0.011
to $0.019 per run at API list price as Claude Code reports it (plan quota in practice, no API dollars). The
assessment's $0.30-per-run estimate for the SDK arm assumed 40K uncached input tokens per call; with prompt
caching, our loop's list-price figure for the same task is about $0.01. Whether the SDK's tool runner caches is
not stated in its sources.

## What was built

A fixed form task that both arms can run unchanged, so the only thing that differs between them is the loop.

| File | Role |
|---|---|
| `fixture/crm.html` | A CRM page shaped like the launch video's FIG 3: nav, a scanned-card panel (prev/next, zoom), a 9-field lead form (5 text boxes, plan select, seats number, follow-up radio pair, notes), Clear, Save lead, and a leads table. The form is rebuilt after every save, so handles taken before a save go stale, which is the condition the video shows its loop recovering from. |
| `fixture/cards/card-{1,2,3}.png`, `gen_cards.py` | The three handwritten cards, rendered from `expected.json`. Cards 1 and 2 are readable at the default 65% zoom; card 3 is small red cursive and needs enlarging, as in the video. |
| `expected.json` | Ground truth: the three cards' text as shown in the video (frames f-015, f-019, f-023, f-024). |
| `server.py` | Serves the page and appends every Save POST to a JSONL file. The server, not the page, is the record, so a run is scored on what was actually submitted. |
| `score.py` | Wrong fields (9 per lead, a missing lead counts 9), extra saves, tool calls by tool, wall and API seconds, tokens, from the saved JSONL and the stream-json transcript. Exact match after trim, whitespace collapse and case fold; phone compares digits, seats compares as an integer, notes fold dash and quote variants. |
| `run-ours.sh` | One run of our loop: headless Claude Code 2.1.293 on `claude-haiku-5-5` (the video's model), tools limited to Bash and Read, Bash allowed only for `agent-browser`, the agent-browser skill appended to the system prompt, user settings and hooks not loaded, one named `agent-browser --session` closed by name on exit. Appends one JSON line to `results.jsonl`. |

Positive control, before any model run: one lead entered by hand through `agent-browser` with a planted error
(the notes' final period dropped). The server recorded the save and the scorer reported exactly 19 wrong fields:
18 for the two unsaved leads and 1 for the planted error. Phone formatting differences were not counted, as designed.

## Method

1. The harness opens the page in a fresh `agent-browser` session at 1280×800 before the clock starts, as the
   video's FIG 3 begins on a loaded page.
2. The prompt (fixed text in `run-ours.sh`) asks for each card to be entered exactly as written and saved once,
   reading cards from screenshots viewed with the Read tool.
3. Three runs, each a fresh session and a fresh browser. Recorded per run: tool calls, wall-clock seconds,
   wrong fields, extra saves, tokens.
4. Reading fixed before the runs, from the assessment: zero wrong fields and a median wall time within 3 times the
   video's 46 seconds (138 s) closes the question as "no change"; anything worse means the gap is real and paying
   for the SDK arm becomes the operator's call.

The skeptic pass weakened that reading, and the objection stands: what the video's 46 seconds covers, which driver
ran it and whether calls were batched are not stated, so 138 s is a convention, not a measured bar. The numbers
below are first of all a baseline, which no store held before (per-site success, latency and token cost for
`agent-browser` runs were recorded nowhere).

Pilot run (discarded): two harness defects showed up in the first run and were fixed before the measured runs.
The prompt said to save screenshots "into the current directory", but `agent-browser` resolves a relative path
against its daemon's working directory, so the model spent 3 calls hunting for the file. And the card panel's
default zoom (55%) made every card too small to read, which is harder than the video, where only card 3 needed
enlarging. The prompt now names an absolute directory and the default zoom is 65% in a wider panel.

## Results

Raw lines: `results.jsonl`. Every run's init line reports `claude-haiku-5-5` on 2.1.293.

| Run | Leads saved | Wrong fields (of 27) | Extra saves | Tool calls (Bash + Read) | Wall s | API s | Output tokens | Cached input tokens | List-price $ |
|---|---|---|---|---|---|---|---|---|---|
| t1 | 3 | 1 ("Lena Voyt") | 0 | 21 (14 + 7) | 52.2 | 33.3 | 6,464 | 261,407 | 0.011 |
| t2 | 3 | 1 ("Lena Voyt") | 0 | 29 (19 + 10) | 80.6 | 58.5 | 10,175 | 644,458 | 0.019 |
| t3 | 3 | 0 | 0 | 20 (13 + 7) | 153.8 | 134.2 | 6,047 | 344,228 | 0.012 |
| median | 3 | 1 | 0 | 21 | 80.6 | 58.5 | 6,464 | 344,228 | 0.012 |
| video (SDK loop) | 3 | 0 (one run) | n/a | 67 | 46 | not stated | not stated | not stated | not stated |

What the numbers say:
- Calls are about a third of the video's, because Claude Code batches several `agent-browser` commands in one
  Bash call (`fill @e13 … && fill @e14 …`), and one call fills a whole form. A call count is therefore not
  comparable across the two loops; seconds and wrong fields are.
- Wall time varied 3x across runs with similar call and output-token counts, and API time tracks it (33 s to
  134 s). The spread is model latency, not the loop.
- Where our loop loses time: the card panel scrolls inside its own box once enlarged, and one measured run
  (and the pilot) tried a page scroll first, which does not move it. The video's loop has a crop `zoom` tool and does not need to scroll.
- The model enlarged card 3 in every run, unprompted.

Harness defects found and fixed during the runs (all outside the timed window, so no measurement is affected):
- Scorer: it paired a saved lead to a card by exact name, so t1's single misread letter first scored as a missing
  lead (9 wrong) plus a stray save. It now pairs by best match; t1 was rescored from its raw data.
- Watchdog: its `sleep` outlived it and held the caller's output pipe open, stalling the next run for up to the
  full 900 s bound. Fixed; checked live after t3 (no leftover `sleep`).
- A first t3 was stopped and discarded because `run-ours.sh` was edited while it ran (bash reads a script as it
  goes, so its post-run steps were unreliable). The t3 above is a clean rerun.

## The SDK arm (not run)

It needs, all operator-owned: a Console API key, the Max-plan monthly API credit (announced 2026-10-07 as rolling
out "this week"; not observed on any account when the row was filed) or other API billing, and an explicit
authorization to spend it (`accounts.json` `spend.usage_credits_authorized` is `false`, and no store records an
authorization for API-key spend). It also needs `anthropic>=1.12.0` (0.105.2 is installed) and a small CDP driver
for the browser toolset class. Estimated cost per run: about $0.30 on Haiku 5.5, about $5 to $11 on Sonnet or Opus
5.5 (the assessment's arithmetic, re-checked by the skeptic; output and image tokens not included).

To run it, reuse `fixture/`, `server.py`, `expected.json`, the prompt text and `score.py` unchanged, write the
saved leads to the same JSONL shape, and append to a separate `results-sdk.jsonl`.

## The row's falsifier was broken

The row stored the sentence "an API credit balance is visible in the Claude Console for one of the four accounts"
as its falsifier. The premise checker runs a falsifier as a shell command, so it exited 127 on every pass
("COULD NOT ASK"). It was also the wrong direction: a falsifier exiting 0 closes the row as no longer needed, and
credit becoming visible is when the row becomes actionable, not moot. Of the 18 open rows carrying a falsifier,
this was the only prose one, so the fix is to this row, not to `cc-backlog add`.
