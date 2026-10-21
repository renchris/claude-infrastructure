## F1 — It measured deaths and never looked at wakes
Verdict: REACHED
Parts: re-engagement happens anyway (operator prompt / harness wake): present; audit carried by the next prompt or wake: present
Quotes:
> "The missing piece is the moment of re-entry, not detection."
> "Every observed recovery re-entered the turn from context."
> "The fix is to run the disk audit in a hook and put its verdict table into the wake message. The model's first context after a death is then the ledger, not its own narrative."
> "The automation has to be the reconciliation, not the re-prompt. Any auto-resume that re-enters from context reproduces the defect faster, and without the operator's warning paragraph. ... The audit has to be inside the wake."
Reason: The output states that dead sessions are re-entered anyway (E11 documents two observed re-entries) and moves the design target from detection to the re-entry. It commits to putting the audit's verdict table into the wake message (D6). That is the wake-as-design-target claim, not a detector-only design.

## F2 — The error record's timestamp is not the death's time
Verdict: NOT REACHED  (PARTIAL note: the output does say the api-error record is written long after the silence began, but it attributes this to machine sleep rather than a client retry ladder in a live process, and it does not apply it to a time-window RUNNING rule misreading live units during an outage)
Parts: record written long after connectivity loss: present (as sleep, not retries); client retries for tens of minutes while the process is alive and the transcript is silent: absent (the output says "Retries do not run while the machine sleeps"); applied to unit liveness / `active < 5 min` window misreading live units during an outage: absent
Quotes:
> "The death record marks the end of the silence, not its start"
> "The death record is written when the silence ends (E10): up to 93 minutes after the last real record. Any window keyed on synthetic timestamps is late"
> "The dominant cause is suspension (E9, E21). Retries do not run while the machine sleeps, and longer timeouts stretch the post-wake hang, during which nothing is written to disk"
> "the teammate rule already misreads long tool calls (E13)"
> "on 09-09, 0 delegated units spanned the silence."
Reason: The timestamp-lag symptom is there, but the mechanism the output commits to is suspension during sleep. It explicitly denies that retries run during the gap, so the retry-ladder mechanism is missing. Its criticism of the 300 s teammate window rests on long tool calls, not on live units misread during an outage, and it states that no units spanned the outage. The required application to unit liveness during an outage is therefore missing.

## F3 — The stall is a symptom, not a third cause
Verdict: REACHED
Parts: rejects stall as a third cause: present; same outage seen through the watchdog's shorter timeout: present; independent discriminator (other sessions' activity / probe): present
Quotes:
> "A stall is a third channel for the same causes, not a third cause."
> "the watchdog fires only on a silent API stream with no tool in flight (E5). So a stall is a dead socket (sleep, network), a server that never answered, or a schema loop."
> "Control arm: did any other session write real output during the stall's silent window? No: SLEPT or transport, re-run verbatim. Yes: STALLED, the request is the suspect"
Reason: The output rejects stall as its own cause class and identifies it as the watchdog's view of the same outage. It decides the cause with evidence independent of the stall: fleet-wide activity in the same window. That matches the criterion.

## F4 — Stop hooks do not run on an api-error turn end
Verdict: REACHED  (note: the fact is stated through the binary's own text quoted in E1, and the design premise follows from it; the output never writes a standalone prose sentence saying "Stop does not run")
Parts: Stop does not fire on an api-error turn end: present (measured from the 2.1.260 binary); recovery cannot be armed at the death by a Stop hook: present as a design premise (the watcher is armed earlier and probed for survival; StopFailure output is ignored)
Quotes:
> "Fires instead of Stop when an API error (rate limit, auth failure, etc.) ended the turn. Fire-and-forget — hook output and exit codes are ignored."
> "P2: does a Stop-armed asyncRewake watcher survive a turn that ends in StopFailure, and does its exit 2 wake the idle session?"
> "Why not wake from StopFailure itself: its hook output and exit codes are ignored (E1)."
Reason: The output cites, as measured evidence from the incident's harness binary, that an api-error turn end fires StopFailure instead of Stop. Its design never arms recovery at the death through a Stop hook. Instead it relies on a watcher armed earlier and asks whether that watcher survives the StopFailure turn. The hazard is identified and adopted as a design premise.

## F5 — The harness's own re-engagement path is the substrate
Verdict: REACHED
Parts: harness-originated, keystroke-free wake named: present (asyncRewake exit 2); replaces the operator's typed paragraph: present; audit placed on it: present
Quotes:
> "Before waking: run lr-audit.py (disk only, seconds) and exit 2 with: the gap count; one line per gap with its action; RUNNING units by name, marked "do not re-fire""
> "No keystrokes: never type into live panes for BLACKOUT or API rows."
> "Keystrokes land on whatever owns the pane. ... asyncRewake injects without keystrokes"
Reason: The output names the hook-synthesized asyncRewake exit-2 wake as the re-entry mechanism and rejects typing into panes. It puts the lr-audit verdict into that wake. Its Q5 "zero-paragraph" answer explicitly replaces the operator's paragraph.

## F6 — `turn_duration` separates in-flight from idle
Verdict: NOT REACHED
Parts: named on-disk turn-end record, shown present at both normal and api-error turn ends: absent; used to separate a mid-retry in-flight turn from idle: absent
Quotes:
> "A session is healthy-idle if and only if its last assistant record is non-synthetic with stop_reason:"end_turn" (E18), and every unit it launched has a terminal record or a live owner (D3)."
> "Any idle session that is not healthy-idle is interrupted, whatever killed it."
Reason: The nearest passage uses the assistant record's `stop_reason:"end_turn"` to separate healthy idle from interrupted. It assumes the session is already known to be idle and does not separate a turn still running (mid-retry) from an idle one. It names no `turn_duration` or equivalent marker shown to exist at both normal and api-error turn ends.

## F7 — The retry files were never opened
Verdict: REACHED
Parts: repeated attempts under one journal key: present; watchdog kill written as a user interrupt and misattributed to the user/TaskStop: present; under-count: absent (the output describes an over-split into 6 gaps instead)
Quotes:
> "Fixer slot (journal key v2:a990db…): ... Attempts 2–6 each restart from the 29,815-char original brief, write 7 records and zero assistant output over about 17 min, and end in [Request interrupted by user]."
> "The journal parser keeps only started/result (:439, :441), so the fixer's 6 attempts become 6 separate gaps. The watchdog's [Request interrupted by user] marker (:232) yields INTERRUPTED, "TaskStop / user" (:288)"
> "It also blames watchdog kills on the user."
Reason: The output opened the slot's per-attempt records and journal. It reports six attempts under one key and states that the watchdog's kill is written as `[Request interrupted by user]` and attributed to "TaskStop / user". Two of the three parts are present (repeated attempts plus misattribution), which meets the requirement.

## F8 — "No partial results" is not universal
Verdict: NOT REACHED  (PARTIAL note: the output adds a remote re-read before re-running ambiguous writes made inside the blackout span, but it never makes re-run safety depend on the unit's class)
Parts: re-run safe only for read-only/idempotent units: absent; doubling/damage hazard for side-effecting units (committing teammates, writing slots): partially present (write-level, span-limited); recovery verdict/action depends on unit class: absent (ORPHANED re-runs uniformly)
Quotes:
> "ORPHANED | no terminal record, and no live process that ... | re-run; the harness itself says the state is lost (E6)"
> "Ambiguous writes: before re-running any write attempted in that span (push, land, PR, backlog change), re-read the remote. A client-side failure can be a server-side success."
> "A recovery re-run pays full price unless it seeds from salvage."
Reason: D3 applies a single "re-run" action to every ORPHANED unit, whatever its type. The ambiguous-writes guard is a per-write check limited to the blackout span. It does not say that re-running a unit from scratch is unsafe for side-effecting units, or that the verdict must depend on whether the unit is read-only or side-effecting. The salvage remark is about cost, not a doubling hazard.

## F9 — The ask is an agency problem, not a trigger problem
Verdict: REACHED  (note: the output never uses the words "human as runtime"; the reframe is from detection to re-entry, with the system's wake replacing the operator's paragraph)
Parts: explicit reframe away from detection/trigger: present; the human currently does by hand what the system's wake should do: present (operator's paragraph / typed /limit-recover); commits to a design where the system owns the act: present (D6)
Quotes:
> "The framing assumed a non-quota interruption is a new kind of death that needs a new detector. The disk shows three things that contradict this"
> "The missing piece is the moment of re-entry, not detection."
> "Any auto-resume that re-enters from context reproduces the defect faster, and without the operator's warning paragraph. ... The audit has to be inside the wake."
Reason: The output explicitly rejects the ask's framing as a detector or trigger problem. It locates the gap in re-entry, which the operator's paragraph currently supplies by hand. It commits to a harness wake (D6, Q5 "zero-paragraph") that does that act in the operator's place. The mechanism matches the criterion, although the wording differs.

k = 6 of 9
