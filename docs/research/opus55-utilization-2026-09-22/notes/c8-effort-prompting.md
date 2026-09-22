# c8-effort-prompting — notes (effort.txt [linked], prompting.txt [primary])

Sources: /tmp/opus55-src/effort.txt (Effort docs, linked from the prompting guide; tier "linked") and
/tmp/opus55-src/prompting.txt ("Prompting Claude Opus 5.5", operator-supplied; tier "primary").
HTML originals were spot-checked (keyword counts) — the .txt renders are complete; no table lost.
Neither page carries a chart or any numeric per-effort score/token/cost table. Every quantitative
claim is qualitative ("matches or exceeds", "much lower cost") except: >30% faster output, 128,000
max_tokens, 64k starting max_tokens (Opus 5/4.8/4.7), "five" silent steps, "two or three"
continuations/reminders, "elapsed 340s / 1200s" example, "roughly halved" silent stretches.

## Effort page (effort.txt)

### How effort works (L71-85)
- "Most Claude models default to high effort ...; Claude Opus 5.5 defaults to medium." (L73)
- Setting effort to the model's default == omitting it (L77).
- Effort affects ALL output tokens: text, tool calls + args, thinking (L79-84). "Because effort
  applies to every output token, it works whether or not thinking is enabled. Lower effort also
  means fewer and terser tool calls." (L85)

### Effort levels table (L87-103)
| level | description | typical use case |
|---|---|---|
| max | absolute max, no constraint on spending. Available on Fable 5.1, Mythos 5.1, Fable 5, Mythos 5, Mythos Preview, Opus 5.5, Opus 5, Opus 4.8, 4.7, 4.6, Sonnet 5, Sonnet 4.6 | deepest reasoning |
| xhigh | "Extended capability for long-horizon work." Available on Fable 5.1, Mythos 5.1, Fable 5, Mythos 5, Opus 5.5, Opus 5, Opus 4.8, 4.7, Sonnet 5 | "Long-running agentic and coding tasks (over 30 minutes) with token budgets in the millions" |
| high | default on every effort model except Opus 5.5 | complex reasoning, difficult coding, agentic |
| medium | default on Opus 5.5 | agentic tasks balancing speed/cost/perf |
| low | most efficient | "Simpler tasks that need the best speed and lowest costs, such as subagents" |
- "Not every model that supports max supports xhigh." (Opus 4.6, Sonnet 4.6 have max, not xhigh.)
- Haiku 4.5 appears in NEITHER availability list and not in the Compatibility list (L302-307).
- "Effort is a behavioral signal, not a strict token budget. At lower effort levels, Claude still
  thinks on sufficiently difficult problems, but thinks less" (L101).
- "The per-model recommendations that follow override this table where they differ." (L103)

### Per-model recommendations
- Fable 5.1 (L105-109): supports all five; start with high (default); step up to xhigh/max for "the
  most capability-sensitive agentic and coding work"; step down to medium/low "for routine or
  latency-sensitive work once your evals show quality holds". At high and above set large
  max_tokens (hard limit on thinking + text). Same for Mythos 5.1. Supports per-message effort.
- Fable 5 (L111-115): start high; xhigh for most capability-sensitive; medium/low routine. "Lower
  effort settings on Claude Fable 5 still perform well and often exceed xhigh performance on prior
  models." Reduce effort if a task completes but takes longer than necessary. Same for Mythos 5.
- **Opus 5.5 (L117-119)**: all five levels; medium default; "a request that omits effort runs one
  level lower than it did on Claude Opus 5". "Adaptive thinking is always on and can't be turned
  off, so effort is the primary control for how much the model reasons and what a request costs."
  Run an effort sweep on own evals rather than carrying settings over; large max_tokens at higher
  levels; thinking:{type:disabled} -> 400 at every effort level; supports per-message effort
  (preserves prompt cache). NO use-case -> level mapping is given beyond "medium is the default".
- Opus 5 (L121-133): start high; xhigh for demanding coding and agentic; max when task justifies
  unconstrained spending; "use low and medium liberally as your primary control for token cost and
  response time wherever your evals show quality holds". "Effort controls thinking volume, not
  visible response length: on Claude Opus 5, changing effort does not reliably shorten responses,
  so prompt for length instead." API default high. Thinking cannot be disabled at xhigh/max (400).
  xhigh/max: large max_tokens, start at 64k. Supports per-message effort.
- Opus 4.8 (L135-141): same guidance as 4.7: start xhigh for coding + agentic; high for most other
  intelligence-sensitive; medium/low only when measured. 64k max_tokens start.
- Opus 4.7 (L143-159) table: low = short scoped tasks, pair with explicit checklists if multiple
  sections; medium = drop-in for average workflow; high = "often the best balance of quality and
  token efficiency"; xhigh = recommended start for coding/agentic "and for exploratory tasks such as
  repeated tool calling, detailed web search, and knowledge-base search. Expect meaningfully higher
  token usage than high."; max = frontier problems, "significant cost for relatively small quality
  gains", can overthink on structured-output tasks. 4.7 respects effort more strictly than 4.6 at
  low/medium: scopes work to what was asked. "If you observe shallow reasoning ... raise effort
  rather than prompting around it." Fallback line: "This task involves multistep reasoning. Think
  carefully before responding."
- Sonnet 5 (L161-169): defaults to high "on the Claude API and Claude Code". xhigh for hardest
  coding/agentic. "Medium effort: Cost-saving step-down from the default. Comparable to Claude Sonnet
  4.6 at high effort." Low for high-volume / latency-sensitive, chat and non-coding. Max unconstrained.
- Sonnet 4.6 (L171-178): medium = recommended default for agentic coding, tool-heavy, codegen.

### Effort with tool use (L180-194)
Lower: combine ops into fewer tool calls, fewer tool calls, act without preamble, terse
confirmations. Higher: more tool calls, explain plan first, detailed change summaries, more
comprehensive code comments.

### Effort with thinking (L196-204)
- thinking param controls WHETHER; effort controls how much work across the whole response incl.
  how often/deeply it thinks in adaptive mode. "Don't pass adaptive as an effort value".
- "In a tool-use loop, follow-up requests that only process tool results can still skip thinking at
  any level. At lower levels, Claude can skip thinking entirely for simpler problems."
- Opus 4.5 only: effort + budget_tokens together.

### Change effort mid-conversation (L206-270)
- Per-message effort: Fable 5.1, Mythos 5.1, Opus 5.5, Opus 5 — keeps prompt cache. Others: new
  top-level value on the next request, "which starts the cache over".
- Beta header mid-conversation-output-config-2026-07-01. Fable 5 (and other unsupported) -> 400
  "output_config.effort requires a model that supports per-turn effort; this model does not."
- Mechanism: role "system" message, empty content, output_config.effort; takes effect from next user
  turn, holds until changed; prefix unchanged so cache still matches; may appear anywhere incl.
  first entry. Example: start high, drop to low for a routine follow-up.
- Fable 5.1: prefer per-message; top-level change "restarts the cache and also steers the model less
  reliably: its earlier replies were written at the previous level, and it tends to stay consistent
  with them." (stated for Fable 5.1 specifically)
- Top-level effort shapes the rendered prompt; changing it invalidates cached prefixes. Without
  per-message support, pick one level at the start and keep it constant.

### Best practices (L272-278)
1 set explicitly; 2 low for speed-sensitive/simple ("can significantly reduce response times and
costs"); 3 test your use case; 4 dynamic effort — "Simple queries may warrant low effort while
agentic coding and complex reasoning benefit from high effort"; 5 hold top-level constant within
cached conversations; vary across workloads; use per-message where supported.

### Next steps (L284-298)
- "Task budgets: Give Claude an advisory token budget for the full agentic loop to help the model
  self-regulate on long agentic tasks." (no details on this page)

## Prompting guide (prompting.txt)

### Intro (L15-33)
- ">30 percent faster" output-token generation than Opus 5; "tends to finish the same task with
  fewer tokens". Opus 5 prompts "should perform well without changes". Four breaking API changes
  are in the migration guide (not in this chunk).

### Capabilities relevant to prompting (L35-42)
- Agentic coding/code review: strongest on multistep real-repo work. "at its default medium effort
  the model matched or beat Claude Opus 5 at high effort on such tasks, in fewer steps and with fewer
  tokens." Sustains long-running autonomous work better than Opus 5: "multi-hour audits and
  migrations of large code bases run end to end with parallel subagents and little oversight."
  Early testers: stronger code review, more bugs caught, fewer false alarms; plain-language
  explanations.
- Knowledge work: "much less likely to state an incorrect figure or cite the wrong source"; better
  financial modeling; catches easily-missed details in large inputs (wrong weekday in a long
  thread; chart not matching figures); outputs need less editing.
- Communication: reports on agentic work say plainly what it did, found, needs.
- Visual: "even at its lowest effort setting it read values off dense charts more accurately than
  Claude Opus 5 did at its highest, using a small fraction of the output tokens." Better on
  positional meaning (flowchart arrows, diagram diffs, calendar screenshot times). Computer use: "at
  its default effort it matched the success rate that Claude Opus 5 reached only at a much higher
  effort setting."

### Calibrate effort (L44-54)
- Start at medium; set explicitly; test several levels; don't carry over Opus 5 setting.
- "Effort level names don't correspond to the same amount of thinking across models: ... Claude Opus
  5.5 at medium matches or exceeds Claude Opus 5 at high on coding and knowledge-work evaluations,
  and on several coding evaluations low comes close to it at much lower cost."
- "At a given level, Claude Opus 5.5 tends to think more per turn than Claude Opus 5, especially at
  xhigh and max. If you keep the effort value you set for Claude Opus 5, expect longer turns and
  more output tokens."
- Three adjustments: (1) max_tokens room for thinking; thinking counts toward max_tokens even when
  not returned; "a max_tokens of 128,000, the model's maximum, has worked well" for long agentic
  coding turns. (2) "Reserve xhigh and max for work where you've measured a quality gain." (3) "To
  get less thinking, lower the effort level first ... more reliably than prompt instructions do."
- Top-level effort change invalidates cache; use per-message effort (beta).

### Prompts written for thinking disabled (L56-63)
- Opus 5 accepts thinking disabled at high or below; Opus 5.5 does not.
- Start at LOW effort and measure; at low thinking stays short; how often it skips thinking entirely
  depends on prompts; move to medium if quality drops. TTFT lever: "Answer directly without
  deliberating." (may lower quality).
- Remove "write your reasoning in the response" instructions; read summarized thinking
  (display:"summarized"); such prompts can be declined as reasoning_extraction.
- Re-test thinking-disabled mitigations (combined instruction; remove no-thinking rule either way).
- Read response by block type; thinking field empty under default display:"omitted".

### Unattended agentic runs (L65-81)
- Updates can end a turn with text (stop_reason end_turn); a loop that treats that as done stops.
- "Treat a text-only end of turn as a report rather than as proof the task is done." Keep a
  checklist (todo tool or file). If items open and no blocker, send a short user message naming them
  (example given). Or state completion condition up front and "have a separate, smaller model check
  the conversation against it at each end of turn". "stop after two or three automatic
  continuations on the same task rather than repeating them indefinitely".
- If a background command or subagent is still running, don't treat as done; wait and return its
  output as next user message.
- System-prompt addition: model is responsive to instructions naming the specific early stops to
  avoid, and naming wanted stops. Full example paragraph (four unwanted stop kinds: summary that
  announces next step w/o tool call; offer to carry on unless user prefers otherwise; list of
  non-blocking decisions; deciding it's a good place to report). Add at END of system prompt from
  FIRST request — adding mid-way changes system prompt and invalidates earlier thinking blocks
  (Preserved thinking). Status notes go into the tool-call message -> arrive as progress updates
  (empty at default display; set display:"updates"). Keep own confirmation step for risky/
  irreversible actions; leave it OUT of human-in-the-loop apps. "Expect somewhat more tool calls
  and output tokens per task."

### Safeguard refusals (L85-93)
- Classifiers: biology, cybersecurity, reasoning extraction.
- Biology safeguards = Fable 5.1's; new vs Opus 5; everyday health unaffected; Life Sciences
  Verification Program.
- Cyber: "Finding vulnerabilities in source code is allowed. High-risk dual-use cybersecurity
  activities are not."
- Reasoning extraction: new vs Opus 5.
- Decline = normal response, stop_reason "refusal", stop_details names category. Can retry
  automatically on a fallback model, "except for reasoning_extraction declines, which server-side
  fallback returns to you instead of retrying". (Fallback model identity NOT named here.)

### User-facing progress updates (L95-107)
- Short updates between tool calls come back as progress-update THINKING blocks with empty text at
  default thinking.display; text-only clients look silent. display:"updates" (beta header
  thinking-display-updates-2026-08-18).
- Verbatim mid-turn content: give a simple send-message tool; declare it in tools from the first
  request (adding later edits prefix, invalidates earlier thinking blocks).
- More predictable updates: say so in the system prompt; "helps most in human-in-the-loop work".
- Harness nudge: count consecutive tool steps with nothing to read; after several ("five, for
  example") append reminder as a turn-scoped system message (clear_at:"next_user_message"; beta
  header mid-conversation-system-clear-at-2026-08-21); stop after two or three reminders; appended
  and left in place so cache keeps matching and thinking blocks stay valid. Result: "roughly halved
  the share of tasks with a long silent stretch, with no measurable change in cost" (agentic coding).

### Multi-app workflows (L111-119)
- "Claude Opus 5.5 tends to get to work quickly"; on loosely specified tasks tell it to look through
  sources first. Explore-broadly sentence given. Result: "completed noticeably more of them
  correctly with this instruction, at both medium and max effort, at the cost of slightly more tool
  calls and tokens". Keep untrusted content out of searched records.

### Time signals for multi-agent harnesses (L121-129)
- Model "pays close attention to information about elapsed time"; in lead->subagent setups use it
  "to speed up the work through better parallelization".
- Budget: harness appends "elapsed 340s / 1200s" to each message; model paces to finish inside,
  "usually finishes well before it" -> set budget somewhat above desired; tune on sample tasks.
- No budget: show elapsed alone + "Time matters here: do not spend time that can be avoided, and
  the earlier a correct result is obtained, the better."
- "In Anthropic's evaluations of small agent teams on research tasks, both signals made teams
  finish sooner than a single agent working without them. Teams given a budget kept answer quality
  comparable to the single agent's while finishing considerably sooner."
- "A tighter budget has a different effect from a lower effort setting: lowering effort reduces the
  work itself, whereas a budget mostly keeps more agents working in parallel."
- Advisory; keep own hard timeout; "under time pressure the model may search and verify a little
  less". (No team size, no speedup number, no lead/worker model/effort mix given.)

### Chat thinking instructions (L131-141)
- Remove "think carefully before answering" lines in chat: replies start sooner, "no clear decline"
  in quality. Effort is the main control.
- Multi-turn: model sometimes re-examines earlier answers even on short follow-ups (more thinking,
  latency). Settle-answers two sentences reduce follow-up thinking without affecting quality. Leave
  out for long analyses / agentic tasks where a later step can reveal an earlier mistake; may make
  the model less likely to volunteer a mistake in an earlier answer.

### Pasted text (L143-161)
- "resists indirect prompt injection ... better than any earlier Opus model" (tool results, web
  pages, on-screen/browser content). With pasted_content tags carrying a shared random id + system
  note, robust against instructions in user-pasted content. May make model slightly more cautious;
  tags are plain text and imitable — one guardrail among several.

### Visual inputs (L163-165)
- Re-test old visual scaffolding. For densest inputs: higher-res images (esp. technical drawings);
  image tools in a container (PIL, OpenCV) to crop/zoom/measure/verify; crop tool alone still helps.
  "The model uses these tools more effectively at higher effort levels. Without tools, raising effort
  improves its reading of technical drawings but does little for charts."

### Frontend (L167-171)
- Falls back on default styles; generic "avoid AI look" swaps one default for another; name specific
  patterns to avoid; iterate.

## Absent (utilization questions not answered here)
See StructuredOutput `absent`.
