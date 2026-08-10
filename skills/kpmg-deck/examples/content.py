"""
content.py -- the course deck's argument, as data.

WHY THIS FILE EXISTS AND WHY IT IS NOT IN course.py.

The 22 CLAIMS ARE DELIVERED MATERIAL, verbatim from COURSE.md, and they are not up for
rewriting -- they were written for a room, reviewed, and shipped. Everything else here is the
SUPPORTING material each claim needs in order to be a page rather than a poster: a standfirst,
a body, and one exhibit.

That split is the whole point of C1 of the build spec. The previous deck called
`d.statement(claim)` with no second argument thirty times, and the result measured a median of
69 characters a page against KPMG's 2,275-2,422, with 28 of 37 pages under 8% ink. The claims
were never the problem. The absence of anything beside them was, and the fix is content, not
composition -- a coloured void is still a void.

THE DENSITY TARGET IS THREE ELEMENTS, NOT MORE WORDS. Copying KPMG's own 2,400 characters a
page would be the opposite error: that density is right for a desk-read InDesign report and
wrong for 140 people looking at a projector. Each page here carries the claim plus two of --
a chart, a large figure with a gloss, an attributed quote, a two-column contrast, a labelled
diagram, or a worked terminal example.

Every supporting line is drawn from the delivered course material in COURSE.md. Nothing here
asserts anything the course does not already say.
"""

# The six sections: title, content-minutes, and the section's own claim.
SECTIONS = {
    1: (
        "Set up a clean workspace",
        57,
        "An agent that cannot find your work will confidently invent it.",
        "A folder is not a filing convenience. It is the entire world the agent can see, "
        "and anything outside it does not exist. Open it on work you actually owe someone "
        "this week, not on a sandbox.\n\n"
        "Then stop moving files around. Point at what you already have; a copy drifts the "
        "moment you make it and a pointer cannot. The editor is for reading the result. "
        "The terminal is where the work happens.",
    ),
    2: (
        "Connect it to your real systems",
        28,
        "An agent gets the access you already hold, and no more.",
        "Local files are the easy half. Jira, Confluence, GitHub, SharePoint, OneDrive, "
        "Snyk, Postgres, AWS -- eight platforms, one mechanism. Each issues you a token "
        "that lets an agent read, create, update and delete exactly as you can.\n\n"
        "Nothing about the risk changes when the agent types the statement rather than you. "
        "Your credential, your permission, your responsibility. The failure mode worth "
        "fearing is adopting nothing.",
    ),
    3: (
        "The source, and the session",
        54,
        "Context degrades from the first token, so reset on the work, not on a number.",
        "The window holds five or six textbooks, and most of it is not your words. "
        "Degradation is continuous from the first token; there is no threshold where it "
        "starts.\n\n"
        "So the session is disposable and the file is the asset. Write down the decisions, "
        "the reasoning and what you ruled out, then clear. A fresh session that has to be "
        "re-explained anything means the file caught findings but not reasoning.",
    ),
    4: (
        "Plan until nothing is ambiguous",
        61,
        "Front-loading the thinking is cheaper than correcting the output.",
        "Take your rawest client material and do not tidy it. Ask for every distinct "
        "request, every contradiction, and the question nobody has asked yet -- while the "
        "relationship is still live enough to go and ask it.\n\n"
        "Then research, then plan, then hand the plan over and leave it alone. The "
        "bottleneck is no longer the work. It is the document you build first.",
    ),
    5: (
        "Sign it off, then make it repeatable",
        62,
        "Anything the agent has to re-derive tomorrow is debt you took on today.",
        "Never sign off blind. Read the criterion you wrote this morning, then read the "
        "pack around it -- what came from what, what you ruled out, the diffs, the output. "
        "Your sense that it went well is not evidence.\n\n"
        "Then make the next run cheaper. Clean history, the smallest correction that fixes "
        "what broke, and a skill file only once the work has earned one.",
    ),
    6: (
        "Stop being the bottleneck: run several at once",
        40,
        "You do not orchestrate the system yourself. You ask for it.",
        "Every hour until now made one agent better, and one agent's throughput was never "
        "the limit. That backlog of tickets, ever-growing and never clearing, is thirty "
        "sessions waiting -- if each ticket is described well enough to hand over.\n\n"
        "Dynamic workflows and agent teams are both out of the box. A few to explore, a few "
        "to validate, a few to red-team. The ceiling moves to how many you can hold in mind.",
    ),
}

# Short handles for the chart axis. A bar label is scanned, not read; the approved titles
# appear on the section openers and in the notes, where they are read properly.
SHORT = {
    1: "Clean workspace",
    2: "Real systems",
    3: "Source and session",
    4: "Plan",
    5: "Sign off, repeat",
    6: "Run several",
}

# The nav strip's own labels. Same handles: a tab is scanned harder than a bar label.
NAV = [SHORT[n] for n in sorted(SHORT)]


# ---------------------------------------------------------------------------
# The 22 claims, each with the two elements that turn it into a page
# ---------------------------------------------------------------------------
#
# kind      how the page is built: "white" | "split" | "field" | "quote"
# claim     VERBATIM from COURSE.md. Not editable here.
# stand     the standfirst -- one sentence, set in Cobalt under the headline
# body      the argument, from the delivered companion material
# element   the third thing on the page, as (type, payload)
#
# element types:
#   contrast  (left_label, left_body, right_label, right_body, emphasis)
#   code      (lines, caption)
#   stat      (value, label, caption)
#   rings     [(value_label, gloss, group), ...]
#   panel     (heading, [(label, body), ...])          -- for "split", the panel's content
#   quote     (text, name, role)                       -- for "quote"

CLAIMS = [
    # -- Section 1 ---------------------------------------------------------
    dict(
        section=1,
        kind="white",
        eyebrow="The claim",
        claim="It is two jumps, not one.",
        stand="Both jumps are real, and both land on the same top level.",
        body="A non-technical professional becomes a technical one. Then a technical "
        "professional becomes an AI-accelerated one.\n\n"
        "Client knowledge is the harder half. An agent closes a technical gap in weeks; "
        "nothing shortcuts years with the client.",
        element=(
            "contrast",
            (
                "The engineer",
                "One rung. The technical half is already held.",
                "Everyone else",
                "Two rungs, same top level.",
                "right",
            ),
        ),
    ),
    dict(
        section=1,
        kind="split",
        eyebrow="The definition",
        claim="An agent is a harness and a model. You do not build one.",
        stand="Both lists will be wrong within a year. The plates do not move.",
        body="A harness is the thing you open and type into. A model is what it calls. "
        "Everything you learn today sits on the join between them, which is why it "
        "survives both lists being replaced.",
        element=(
            "panel",
            (
                "Two plates, and neither is yours to build",
                [
                    ("Harness", "Claude Code · Cursor"),
                    ("Model", "Opus · Sonnet"),
                    (
                        "Why it matters",
                        "Both lists date. The split between them does not.",
                    ),
                ],
            ),
        ),
    ),
    dict(
        section=1,
        kind="white",
        eyebrow="The rule",
        claim="Point, never copy. A copy drifts the moment you make it.",
        stand="A symlink cannot drift. Two copies of the same spreadsheet always do.",
        body="One folder per engagement: what arrived, what you distilled, and a pointer to "
        "anything shared. Nothing is duplicated, so nothing can disagree with itself.",
        element=(
            "code",
            (
                [
                    "engagement/",
                    "├─ inbox/        ← what arrived",
                    "├─ knowledge/    ← what you distilled",
                    "└─ finance → ../shared/finance",
                ],
                "One path, resolved live. Never synchronised.",
            ),
        ),
    ),
    dict(
        section=1,
        kind="split",
        eyebrow="The split",
        claim="The editor is for reading. The terminal is where the work happens.",
        stand="Mission control, not a programming surface.",
        body="Open the editor to read what came back -- rendered markdown, a diff, a file "
        "you can check. The code stays out of sight on purpose. Nobody in this room needs "
        "to look at it, and the moment it is on screen the day becomes a programming "
        "course.",
        element=(
            "panel",
            (
                "Your move",
                [
                    (
                        "Do this",
                        "Find a Word file or PDF already in your folder. Ask the agent to "
                        "convert it to markdown. Open the result.",
                    ),
                    (
                        "You are set up when",
                        "you can read the whole thing in the editor -- and so can the "
                        "agent, with nothing left to decode on every pass.",
                    ),
                ],
            ),
        ),
    ),
    # -- Section 2 ---------------------------------------------------------
    dict(
        section=2,
        kind="white",
        eyebrow="Section two",
        claim="Local files are the easy half. The rest of your work issues you a token.",
        stand="Eight platforms, one mechanism: the access you already hold.",
        body="Jira, Confluence, GitHub, SharePoint, OneDrive, Snyk, Postgres, AWS. Each "
        "hands you a personal access token, and that token lets an agent read, create, "
        "update and delete -- exactly as you can, and never more.",
        element=(
            "stat",
            (
                "8 : 1",
                "platforms to mechanisms",
                "Every one of them issues a personal access token. There is no "
                "second thing to learn.",
            ),
        ),
    ),
    dict(
        section=2,
        kind="white",
        eyebrow="Section two",
        claim="The same statement, twice. Nothing about the risk changed.",
        stand="Your credential. Your permission. Your responsibility.",
        body="If you can drop a production table, so can anything running as you. That was "
        "true before today. What changes is who typed it, and that is not the part the "
        "risk was ever attached to.",
        # A two-column contrast, not a panel. The whole point of this claim is that the two
        # sides are IDENTICAL, and a contrast pair is the only element that can show that --
        # in a panel the repetition reads as an editing mistake rather than as the argument.
        element=(
            "contrast",
            (
                "You type it",
                "DROP TABLE claims_2026;   Your credential, your permission, your "
                "responsibility.",
                "The agent types it",
                "DROP TABLE claims_2026;   Your credential, your permission, your "
                "responsibility.",
                "right",
            ),
        ),
    ),
    dict(
        section=2,
        kind="field",
        eyebrow="Section two",
        claim="Give it less than you hold — and keep three things out of one session.",
        stand="Any two of these are ordinary. All three at once is the one to refuse.",
        body="Private data. Untrusted content. An outward channel. Each is unremarkable "
        "alone and the combination is not. If you can drop a production table, your agent "
        "should not be able to.",
        element=None,
    ),
    dict(
        section=2,
        kind="white",
        eyebrow="Section two",
        claim="MCP is a standard, not a capability. Not having one blocks nothing.",
        stand="No server? Point it at the command line you already have.",
        body="It is the plug-and-play way to reach an API, and often less token-efficient "
        "than the CLI already on your machine. Waiting for a server is a way of not "
        "starting.",
        element=(
            "contrast",
            (
                "With a server",
                "Plug-and-play, discoverable, and one more thing to be approved.",
                "Without one",
                "Point it at the CLI. Same reach, today, with nothing to procure.",
                "right",
            ),
        ),
    ),
    # -- Section 3 ---------------------------------------------------------
    dict(
        section=3,
        kind="white",
        eyebrow="Section three",
        claim="Degradation starts at the first token, not at a threshold.",
        stand="It holds five or six textbooks — and most of it is not your words.",
        body="There is no line the session crosses where quality falls off. It is "
        "continuous, from the very first exchange, and the figures below are the shape of "
        "a session rather than a measurement of one.",
        element=(
            "rings",
            [
                (
                    "89%",
                    "of the window still held where most people are working",
                    "load",
                ),
                (
                    "74%",
                    "of it is not your words — it is tool output and file contents",
                    "load",
                ),
            ],
        ),
    ),
    dict(
        section=3,
        kind="split",
        eyebrow="Section three",
        claim="Reset when the work resolves, not at a percentage.",
        stand="The file is the asset. The session is disposable.",
        body="Same task, same result -- but one run rode the window to 89% and the other "
        "checkpointed at 30% three times. Write everything established to a file: the "
        "decisions, the reasoning, and what you ruled out. Then clear, and read it back.\n\n"
        "You have it when the fresh session picks up without asking you to re-explain "
        "anything. If it re-proposes what you rejected, the file caught findings but not "
        "reasoning.",
        element=(
            "panel",
            (
                "Read it as a stranger",
                [
                    (
                        "Do this",
                        "Read that file as if you had never seen the session that produced "
                        "it. Find one thing a stranger would get wrong, then have it added.",
                    ),
                    (
                        "You have it when",
                        "you find at least one. Nearly everyone does on the first pass, "
                        "which is the point of doing it now rather than next week.",
                    ),
                ],
            ),
        ),
    ),
    # -- Section 4 ---------------------------------------------------------
    dict(
        section=4,
        kind="split",
        eyebrow="Section four",
        claim="It was trained on the best.",
        stand="So it works best with the best — and what it emits drifts to what it saw most.",
        body="Choose the best-in-class framework, database or convention and you get the "
        "tool and an agent already fluent in it. Deviate and you take the hit twice.",
        element=(
            "panel",
            (
                "The whole mitigation",
                [
                    (
                        "Pin your versions",
                        "Explicitly, in the folder, where it will be read.",
                    ),
                    (
                        "Put current documentation in the folder",
                        "It cites what is in front of it before what it remembers.",
                    ),
                    ("That is all of it", "There is no third step."),
                ],
            ),
        ),
    ),
    dict(
        section=4,
        kind="field",
        eyebrow="Section four",
        claim="Front-loading is the cheaper path.",
        stand="The same information, given whole or given in pieces. Shape, not scale.",
        body="One session against four weeks, for the same artifact. The bottleneck is no "
        "longer the work — it is the document you build first, and information given in "
        "pieces is paid for in weeks.",
        element=None,
    ),
    # -- Section 5 ---------------------------------------------------------
    dict(
        section=5,
        kind="white",
        eyebrow="Auto mode",
        claim="Stop being asked about the safe things.",
        stand="Two options when it stops, and only two: approve it, or discuss it until you understand it.",
        body="Never blind. It is on when almost nothing interrupts you, and what does is "
        "worth interrupting for.",
        element=(
            "contrast",
            (
                "Runs unremarked",
                "Navigating into another folder. Reading your files. Safe commands, on its "
                "own judgment.",
                "Stops and asks",
                "Modifying a database. Anything that needs a second look.",
                "right",
            ),
        ),
    ),
    dict(
        section=5,
        kind="white",
        eyebrow="Commit history",
        claim="Anything an agent has to re-derive is technical debt.",
        stand="Clean history is not an aesthetic preference.",
        body="It decides whether the agent spends its intelligence on your hard problem or "
        "on your haystack. The repository with a trail answers from its own history; the "
        "one without re-derives it from the code, out loud and wrong.",
        element=(
            "code",
            (
                [
                    "feat: sign-off pack per deliverable",
                    "fix:  criterion had drifted",
                    "docs: why we ruled out approach 2",
                ],
                "Commit with why, not what. A fresh session answers from this.",
            ),
        ),
    ),
    dict(
        section=5,
        kind="white",
        eyebrow="Agent instruction files",
        claim="The best agent file is no file.",
        stand="Add to them only when something breaks — the smallest correction that fixes it.",
        body="They are ordinary markdown and load themselves every session. What they cost "
        "is not tokens; it is attention. Instruction-following degrades as density rises, "
        "so every line makes every other line less likely to be obeyed.",
        element=(
            "code",
            (
                [
                    "CLAUDE.md   loaded every session, unasked",
                    "AGENTS.md   the same, for other tools",
                    "MEMORY.md   written by the agent itself",
                ],
                "Grown, never pruned, is how these stop being read. Write when it broke.",
            ),
        ),
    ),
    dict(
        section=5,
        kind="split",
        eyebrow="Skills",
        claim="A skill is earned, never authored.",
        stand="A file written from one prompt has never met a real edge case.",
        body="Every use makes the next one cheaper. Research file, agent file, skill file — "
        "all markdown in the folder; only when each enters the session differs.\n\n"
        "And a skill rots at a model upgrade: a file tuned to one model can underperform on "
        "the next. Re-test at every upgrade, and delete what it no longer needs.",
        element=(
            "panel",
            (
                "Illustrative, not measured",
                [
                    (
                        "Run 1 · 100 steps",
                        "The first time, reasoned through end to end.",
                    ),
                    ("Run 4 · 50 steps", "The same work, now mostly recall."),
                    (
                        "Nobody measured these",
                        "They are the shape of the argument, not a finding.",
                    ),
                ],
            ),
        ),
    ),
    dict(
        section=5,
        kind="white",
        eyebrow="Self-improving",
        claim="The model is not learning.",
        stand="You are moving work out of the part that costs thinking.",
        body="Into a script that costs nothing to think about. That is all self-improving "
        "means. The sweep was expensive because the model had to reason its way through it; "
        "it never has to again.",
        element=(
            "stat",
            (
                "once",
                "how many times the reasoning is paid for",
                "Name one thing you do by hand, repeatedly, that should have been a script. "
                "You have it when you are holding that script.",
            ),
        ),
    ),
    # -- Section 6 ---------------------------------------------------------
    dict(
        section=6,
        kind="split",
        eyebrow="The fan-out",
        claim="You do not orchestrate your own engineering system. You ask for it.",
        stand="Dynamic workflows and agent teams — both out of the box.",
        body="A few to explore, a few to validate, a few to red-team. But fan out along the "
        "grain: sub-agents do not share context and cannot see each other's work, so work "
        "that splits well decomposes into pieces that read but do not write shared state. "
        "Keep the writing and the final synthesis single-threaded.\n\n"
        "Most multi-agent failures are decomposition failures, not capability failures.",
        element=(
            "panel",
            (
                "Your move",
                [
                    (
                        "Do this",
                        "Take a real question with several independent parts. Research this "
                        "with several sub-agents.",
                    ),
                    (
                        "Along the grain",
                        "Independent, self-verifiable, and nothing two of them both write.",
                    ),
                ],
            ),
        ),
    ),
    dict(
        section=6,
        kind="white",
        eyebrow="The count",
        claim="A session is per task. A passing thought is a task.",
        stand="Thirty tangents in a client meeting is thirty tasks.",
        body="Five to seven readable sessions per display; around sixteen across three "
        "monitors. Token cost scales with sessions, but the review burden grows faster and "
        "all of it lands on one person. The screens are not the real ceiling.",
        element=(
            "rings",
            [
                ("5–7", "readable sessions on one display", "count"),
                (
                    "~16",
                    "across three monitors — and still not the real ceiling",
                    "count",
                ),
            ],
        ),
    ),
    dict(
        section=6,
        kind="white",
        eyebrow="The entry requirement",
        claim="If you can put it into words, you can be an AI engineer.",
        stand="Talking or typing. That is the whole entry requirement.",
        body="Typing is the gap between having a thought and getting it onto the screen, and "
        "dictation closes it. Tacit knowledge is impractical to type and trivial to talk "
        "through — which is why this course's own source was a dictated monologue.",
        element=(
            "stat",
            (
                "3 hours",
                "of dictated monologue behind this course",
                "Claude Code has dictation built in, macOS has it system-wide, or run an "
                "open-source speech model locally.",
            ),
        ),
    ),
    dict(
        section=6,
        kind="split",
        eyebrow="The ladder",
        claim="Every rung is how many you can hold in mind.",
        stand="No rung requires more technical knowledge than the one below it.",
        body="A beginner holds one conversation in a browser. A beginning AI engineer holds "
        "one agent, with markdown for research and plans. A strong one holds around ten, "
        "through workflows and agent teams. An exceptional one holds a hundred and upward, "
        "on routines and loops.\n\n"
        "The engineer hands off the code and moves up — closer to the client, and to the "
        "decisions that determine outcomes.",
        element=(
            "panel",
            (
                "Held at once",
                [
                    ("one", "a chat interface in a browser"),
                    ("around ten", "dynamic workflows and agent teams, out of the box"),
                    ("a hundred and upward", "agents on routines and in loops"),
                ],
            ),
        ),
    ),
    dict(
        section=6,
        kind="field-navy",
        eyebrow="The close",
        claim="Ten people. Ten translations.",
        stand="That loss is the actual origin of most technical debt. Not incompetence — distance.",
        body="By the time the work reaches the person doing it, the what and the why are "
        "gone. Collapse the chain and one person holds the whole thing, next to the "
        "original requirement: three people, three times as effective, delivering in a day "
        "what took a fortnight — because nine translations stopped happening.",
        element=None,
    ),
]


# The interactive-visualization page, once per section. Same shape every time, which is the
# point: it is a scheduled part of the hour and it should be recognisable as the same
# instruction each time it appears.
INTERACTIVE = {
    1: (
        "What the folder actually weighs",
        "The same words cost more as a PDF than as markdown, and the extra bytes are the "
        "container rather than the words.",
    ),
    2: (
        "Two of these is fine. Three completes a circuit.",
        "Private data, untrusted content, an outward channel. Build the combination and "
        "watch which one you should have refused.",
    ),
    3: (
        "The same task, run twice.",
        "One run rides the window down. The other checkpoints and clears. Same artifact, "
        "different cost.",
    ),
    4: (
        "One word, two artifacts.",
        "Change a single black-box word in the prompt and watch what comes back change with "
        "it.",
    ),
    5: (
        "A skill is earned, never authored.",
        "Run the same job four times and watch the step count fall as the file learns what "
        "the work actually needs.",
    ),
    6: (
        "Ten people. Ten translations.",
        "Collapse the chain one link at a time, and meet the new ceiling on the other side.",
    ),
}
