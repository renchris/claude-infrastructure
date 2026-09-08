# Axis A — --mcp-config / --strict-mcp-config semantics, MEASURED on 2.1.260

Binary: ~/.claude-260/node_modules/.bin/claude (2.1.260). The plan's table was measured on
2.1.220 and 2.1.260 ships a COMPILED binary (bin/claude.exe, 198 MB) — there is no cli.js to
grep, so every answer below is EMPIRICAL, not source-read.

## Method — the marker-file probe (`claude mcp list` is a BLIND instrument here)
`claude mcp list` reports the same set under every flag combination — it ignores both
--mcp-config and --strict-mcp-config. Anything concluded from it would be wrong.
Instead each probe server is a shell script that `touch`es a marker then execs /bin/cat, so the
marker file records that the server was actually STARTED. MCP servers start BEFORE the auth
check, so an unauthenticated throwaway CLAUDE_CONFIG_DIR is a sufficient and hermetic harness
(observed: "Not logged in · Please run /login" AND both markers written).
Harness: /tmp/mcp-probe-A — no live config dir was read or written.

## Results

| invocation | servers STARTED |
|---|---|
| no flags | user + project |
| `--mcp-config=extra.json` | user + project + **extra** |
| `--strict-mcp-config` alone | **NONE** |
| `--mcp-config=extra.json --strict-mcp-config` | **extra only** |

1. **Q1 — MERGE or REPLACE? MERGES.** `--mcp-config` adds to both user-scope and project scope.
   ⇒ the plan's DoD #2 is REQUIRED: injecting the SSOT alone does not de-duplicate anything;
   the six user-scope copies keep being read and keep diverging.
2. **Q2 — does `--strict-mcp-config` kill project `.mcp.json`? YES.** With strict, only the
   --mcp-config file survives; the project server did not start. Per the frozen scope
   ("project .mcp.json layering MUST keep working") **`--strict-mcp-config` is DISQUALIFYING
   as a launcher default.** Bare strict is worse still: zero servers.
3. **Q4 — precedence on name collision** (same name `dup` in all three):
   `--mcp-config` **>** project `.mcp.json` **>** user-scope `.claude.json`.
   Measured: no flags -> project's copy wins over user's; add --mcp-config -> its copy wins over
   both. CONSEQUENCE, and it is a semantic change the plan did not state: an SSOT injected by
   flag OVERRIDES a project's own definition of the same NAME. Additive project servers still
   layer (Q2 result without strict), but a project can no longer REDEFINE a shared name. That is
   what would cure live divergence #1 (~/Development/personal/.mcp.json's npx ms365 loses to the
   SSOT) — a cure by precedence, not by editing that project file.
4. **Q5 — multiple files: YES, both forms work.** Repeated `--mcp-config=` flags merge, and the
   variadic space form accepts several paths. ⚠️ The space form is VARIADIC and swallows the next
   argument: `--mcp-config X mcp list` consumed "mcp" and "list" as config paths
   ("MCP config file not found: .../mcp"). **Always use the `=` form** — this is the same trap
   already recorded in the repo at 03ae59251.
5. **Q6 — `${VAR}` expansion: YES.** A server whose `command` is `${PROBE_CMD}` started correctly
   when PROBE_CMD was exported. ⇒ a TRACKED SSOT can hold secrets by env indirection and commit
   no secret. (Relevant to axis F.)

## Design consequence
The viable shape is **`--mcp-config=<SSOT>` WITHOUT `--strict-mcp-config`, plus stripping the
user-scope copies**. Strict cannot be a launcher default without violating the frozen scope.
