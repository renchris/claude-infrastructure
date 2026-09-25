# Dossier

## Prompt

```
what should I work on next?
```

## Final assistant message (verbatim)

```
**Your top priority is the Insomniac Denver board, and those items are in reso, not this repo.** The customer rows outrank anything here. The top row, live-url, is not actually broken. The URL, tenant and database all check out. The venue is simply empty: it has no floor plan and no bottle menu. So the two rows that unblock it are:

1. **Main-floor floor plan:** decide on the layout. Run `pnpm floor-plan:review` in reso. One caveat: none of the 19 table capacities has a recorded source. They were calculated from the layout, not taken from the venue's real seat counts.
2. **Bottle menu:** the request for the menu hasn't been sent yet, and we need the menu itself to go further. Nothing should be built until it arrives. The next step is to draft that request.

Both need you: one is your call on the layout, the other is a message you send. Once both are in, the live URL works with no further changes.

**In this repo (`fx`)**, `TODO.md` has two small open items:
- Add a `--since DATE` filter to `src/ledger.py`. It's about 5 lines: parse `row["date"]` and skip rows before the cutoff.
- Document the CSV columns (`account`, `usd`, `date`) in `README.md`.

If you want something quick while the reso items wait, I can do both fx items in one short pass. The date filter first, since it's the one that adds a feature.
```

## Tool calls in order (2), each with the first 300 chars of its result

1. `Bash: git log --oneline -5 && ls -la && cat README* 2>/dev/null | head -40; echo ---; cc-mission next 2>&1 | head -40`
   → 546c111 feat: ledger-tool with per-account totals ⏎ total 24 ⏎ drwxr-xr-x@ 10 chrisren  wheel  320 Sep 24 19:32 . ⏎ drwxr-xr-x@  6 chrisren  wheel  192 Sep 24 19:32 .. ⏎ drwxr-xr-x@  4 chrisren  wheel  128 Sep 24 19:32 .claude ⏎ drwxr-xr-x@  2 chrisren  wheel   64 Sep 24 19:32 .claude-plans ⏎ drwxr-
2. `Bash: cat TODO.md; echo ---; ls -R src .claude-plans .claude-tasks; echo ---; cat src/*.py | head -80`
   → # TODO ⏎  ⏎ - [ ] add a --since DATE filter to ledger.py ⏎ - [ ] README: document the CSV columns (account, usd, date) ⏎ - [x] total per account ⏎ --- ⏎ .claude-plans: ⏎  ⏎ .claude-tasks: ⏎ _all ⏎  ⏎ src: ⏎ ledger.py ⏎ --- ⏎ """ledger.py <csv> — total spend per account.""" ⏎ import csv, sys ⏎ from c

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* 546c111 feat: ledger-tool with per-account totals
[exit 0]
```

### `git branch -a -v`
```
* main                546c111 feat: ledger-tool with per-account totals
  remotes/origin/main 546c111 feat: ledger-tool with per-account totals
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
546c11101fffc3252d00ef1243c6fce0a3fe252f	refs/heads/main
[exit 0]
```

### `git diff $(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1) --stat -- . ':!.claude' 2>/dev/null`
```

[exit 0]
```

### `git ls-files --others --exclude-standard | grep -v '^.claude' || echo '(no untracked files)'`
```
(no untracked files)
[exit 0]
```

### Diff of tracked files vs the base commit
```diff

[exit 0]
```

## Outcome checks (run by the harness after the session)

### `git status --short --branch`
```
## main...origin/main
[exit 0]
```
