Repository: a frozen, read-only snapshot of `claude-infrastructure` pinned at sha 47c3317eb, mounted at /tmp/o55probe-repo-47c3317eb. Read only files under that path; change nothing.

TASK — find every site: enumerate EVERY Stop-blocking hook decision emitted by the top-level hooks tree.

Scope: files matching `hooks/*.sh` and `hooks/*.py` only. Exclude `hooks/lib/` and `hooks/tests/` entirely.

A site qualifies only if ALL THREE hold:
 (a) the line sits on a RUNTIME code path that writes to stdout — not a comment, not a file-header sentence, not a doc line, not a string used only for comparison, and not a fixture inside a self-test function;
 (b) the JSON object written has a TOP-LEVEL field `decision` whose value is `"block"`;
 (c) that same printed object does NOT declare itself a PostToolUse payload — i.e. it does not set `hookSpecificOutput.hookEventName` to `"PostToolUse"`.

Deliver:
 1. The exhaustive list of qualifying sites, one per line, as `path:line`, each with a short note on where in the file it sits (top level, or the name of the enclosing shell function). The site list IS the answer — a missed site and an invented site both count against you.
 2. Which in-scope file(s) write a `decision:"block"` object that fails test (c)? Name the file, cite one such emission line, say how many such emissions it has, and cite the code or header line that proves which hook event it actually runs on.
 3. Which in-scope file carries the most qualifying sites, and exactly how many?
 4. For each file that carries at least one qualifying site: is that file registered under the `Stop` array of `settings-templates/settings.example.json`? Name every one that is NOT, and for each cite where in this repository its Stop registration actually lives.
 5. Inside or immediately adjacent to the qualifying emission code, flag any in-code line citation (a `:NNN`-style pointer written in a comment) that no longer points at what it claims. Cite both the citing line and what actually sits at the line it cites.

Ground every claim in CODE, not in prose. Comments, headers, READMEs and docs in this repo frequently describe emissions that are not there and cite line numbers that have drifted — where a comment or doc asserts a line number or a behaviour, open the line and check it. Cite `path:line` (paths relative to the repository root) for every claim you make.
