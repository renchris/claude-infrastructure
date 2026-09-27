# Jev use-case sweep — shared context

The operator asked: across ALL our repositories, is there really no use case for Jev? The prior
investigation searched only claude-infrastructure in depth. Your job: find REAL use cases in your
assigned repo(s), or show with evidence there are none.

## What Jev is (measured; docs/research/jev-at-cost-api-2026-09-18.md §1-2, Addendum 5)
- `typesafe-ai/jev` on Vercel AI Gateway. A typed JUDGE, not a generator. Input: one `state` (text, ≤ ~16 KB)
  plus named questions. Output per question: `boolean` (a probability), `choice` (one key from a map you
  supply, with probabilities), or `score` (a level with a full distribution). No free text, no tool calls.
- ~14.8 calls/min measured (~21k/day). Latency ~0.5-2.5 s. Price now $0.042 per million input tokens,
  $0 output (a 1,000-token call ≈ $0.00004). Calibrated: at p≥0.98 on a 2,000-email phishing benchmark it
  auto-decided 7% at 97.8% precision.
- Privacy: no zero-data-retention on our plan (hobby); standard retention. Customer PII is a real
  consideration — flag it, do not auto-disqualify.
- Integration exists: the `ai` SDK via scripts/jev/evaluate.mjs in claude-infrastructure (Node).

## What counts as a use case
A job where ALL hold: (1) a judgment over short text/structured data that fits a boolean/choice/score;
(2) a CONSUMER that acts on the verdict (code path, queue, operator workflow, customer-facing feature);
(3) it replaces something — an existing LLM call (Claude/OpenAI/etc.), a regex/heuristic with known misses,
or manual human review — or unblocks something not done today.
Priority: anything customer/business-facing (reso venues, guests, reservations, SevenRooms data, the
public web app) > operator workload > internal tooling.

## Deliverable per use case
name · file:line of where it would plug in · the judgment (question + choice keys) · consumer · volume
(measured or estimated, say which) · what it replaces and that thing's current cost/miss rate if known ·
business value in one sentence · privacy class (none / internal / customer PII) · effort (hours) ·
conviction % that it is real value.

## Rules
Read-only. Do NOT call Jev, any LLM API, any network service, deploy, or run app servers. Do NOT run
commands that prompt for permission. Use rg/grep/git/python/cat on files. Write only under /tmp/jev-uc/.
