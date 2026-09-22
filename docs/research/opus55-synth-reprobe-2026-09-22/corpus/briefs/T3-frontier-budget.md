Repository snapshot (read-only, pinned sha 47c3317eb): /tmp/o55probe-repo-47c3317eb. Read ONLY files under that path; do not edit anything.

Explain, end to end and grounded in CODE rather than prose, how this repo bounds a single session's use of the FRONTIER (Fable) model tier. Cite `path:line` (repo-root-relative) for EVERY claim you make — including claims about what is *absent*, where you should cite the file you searched and say what you grepped for.

Cover all of the following:

1. **The enforcer.** Which hook file(s) actually implement the per-session frontier budget, and which PreToolUse tool surface(s) each arm reads. There are two distinct carriers of frontier spend — an in-process Agent-tool spawn and a fired *session* (`handoff-fire.sh`/launcher invoked from Bash). Show the exact code that distinguishes them and the exact code that decides "this request is on the frontier tier" in each case. Quote the predicate; do not paraphrase it.

2. **Where the number comes from, and what it is.** Identify the SSOT file and key the cap is read from, the literal value there today, the exact parsing expression used to read it (note its scoping), and what value is used when the read fails or is non-numeric. Also cover any mechanism that MODIFIES the cap at runtime, its SSOT key, that key's current value, and the exact arithmetic.

3. **Counting and storage.** Where per-session state lives (full path expression), what it is keyed on, what happens when that key cannot be resolved, exactly when the counter is written relative to the allow decision, and whether a refused or failed spawn is refunded. State whether the two carriers share one budget or have separate ones, and cite the code and the test that pin it.

4. **At and over the cap.** Exit code, which stream the message goes to, and how (and why) the two carriers' refusal texts differ. Quote the distinguishing clause of each.

5. **The window.** The `frontier_access` fields the gate reads, the exact comparison it performs, what it does when the window is shut, and — reading the SSOT's current values — whether that branch is reachable in production today. Check what the refusal on that branch advises the caller to use, and compare it against the SSOT.

6. **Kill switches and bypasses.** Enumerate every env var, flag, config state, or command shape that makes the gate not count or not refuse. For each, cite the line that implements it. Separately: the always-resident operator instructions name a kill switch by an env-var name for this ladder — determine whether any executable file in the repo reads it, and say so with the evidence of your search.

7. **Registration — is the session arm actually live?** Determine, from the repo's own config artifacts and migration machinery, whether the Bash (session-fire) arm is wired up by default or is inert. Name the file and matcher group that registers the gate today, name the artifact that would register the other arm, its class, what preconditions it asserts before touching anything, which config directories it writes, and what it verifies afterwards. State the one command a reader should run to establish which state a live machine is in.

8. **Stale/contradicting cross-references.** Several comments and docs cite `path:line` into these files. Check each citation you encounter against the file it points at, and report any that no longer land on the code they describe, plus any doc sentence whose claim is true of the CODE but false of the LIVE WIRING.

Be exhaustive and precise. Where a comment asserts something about behaviour, verify it against the executable line rather than repeating it. A correct answer spans at least four distinct files.
