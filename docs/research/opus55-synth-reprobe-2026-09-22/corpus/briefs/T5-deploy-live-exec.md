In the read-only repository snapshot at /tmp/o55probe-repo-47c3317eb (pinned sha 47c3317eb), find EVERY site that actually EXECUTES `scripts/deploy-live.sh` — every line of shell or Python that causes that script to run as a process, whether it names the path literally or reaches it through a variable, an environment-seam default, a fallback assignment, or a generic dispatcher that is handed the path at runtime.

Search scope: `hooks/` (including `hooks/lib/`), `scripts/` (including `scripts/lib/`), and `bin/`. Ignore `tests/`, `docs/`, `vendor/`, and anything outside those three trees.

What does NOT count as a site — and for each near-miss you reject, say in one line why:
- a mention inside a comment;
- a command that only ends up in front of a human: help text, a banner, a page/escalation record, a hook "reason" blob, a rendered operator-board row, an advisory string stored in a work item;
- a grep/lint pattern, a ratchet-table entry, or a test-fixture literal;
- a bare path assignment that is never invoked;
- `deploy-live.sh` referring to itself, unless it genuinely re-execs itself as a new process.

For each execution site, report:
1. the file path and 1-based line number of the line that performs the invocation;
2. how the target path is resolved at that line — name every intermediate variable and give its own path:line, including any default/fallback;
3. the arguments or flags passed;
4. whether it runs in the foreground, inside a command substitution, or detached/backgrounded;
5. what the caller does with the exit status.

Then, separately: (a) state the total number of distinct execution sites in scope; (b) list every near-miss you rejected, with its path:line and the one-line reason; (c) answer whether `scripts/deploy-live.sh` ever re-execs itself, and whether the only unattended/scheduled entry point that runs it lives inside the three scoped trees or outside them.

Ground every claim in code you have actually read, never in a comment's summary of other code: this tree's comments cite `file:line` into other files constantly and several of those citations are stale against this snapshot — verify any you lean on. Cite path:line for every claim.
