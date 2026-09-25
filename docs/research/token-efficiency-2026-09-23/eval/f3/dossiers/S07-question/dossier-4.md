# Dossier

## Prompt

```
how many of the migrations are c10? which ones aren't
```

## Final assistant message (verbatim)

```
40 of the 41 migrations are `c10`. The only one that isn't is **`0001-migrations-ledger-scaffold.sh`**, which is `mechanical`.

There are 41 files but only 38 numbers, because three numbers have two files each: `0009`, `0016` and `0021`. Every file declares a `# migration-class:` header, so there were no undeclared ones to count.

That means the converger runs only `0001` on its own. The other 40 are staged: each one files a step for you to run.
```

## Tool calls in order (2), each with the first 300 chars of its result

1. `Bash: cd /work/fx/migrations && ls; grep -n -i "c10\|class" README.md | head -40`
   → 0001-migrations-ledger-scaffold.sh ⏎ 0002-curl-gate-scope-registration.sh ⏎ 0003-cloud-fleet-link-drive.sh ⏎ 0004-lead-deathwatch-l1-activation.sh ⏎ 0005-goal-inert-watch-registration.sh ⏎ 0006-coldcompile-admit-registration.sh ⏎ 0007-mailbox-wake-arm-registration.sh ⏎ 0008-auth-timeseries-activatio
2. `Bash: for f in 0*.sh; do printf '%s\t%s\n' "$(grep -m1 -o '^# migration-class:.*' "$f" | sed 's/# migration-class: *//')" "$f"; done | sort`
   → c10	0002-curl-gate-scope-registration.sh ⏎ c10	0003-cloud-fleet-link-drive.sh ⏎ c10	0004-lead-deathwatch-l1-activation.sh ⏎ c10	0005-goal-inert-watch-registration.sh ⏎ c10	0006-coldcompile-admit-registration.sh ⏎ c10	0007-mailbox-wake-arm-registration.sh ⏎ c10	0008-auth-timeseries-activation.sh ⏎ c1

Stop-hook feedback turns: 0. Hook blocking errors: 0.

## Repo state after the run

### `git status --short --branch`
```
## main...origin/main
[exit 0]
```

### `git log --oneline --all --graph -8`
```
* b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
* 48fcf5340 fix(limit-recover): per-sid --one run dir so same-second recoveries keep separate results
* b218c3041 docs(research): token-efficiency round 3 — slim F1 fails on T16, arm closed for now
* b2f5981a7 feat(tokeff-eval): F1 round 3 data — 200 runs with the round-3 slim fix, blind verdicts
* 7140cd89b fix(instructions): slim variant stops re-spelling refused pushes and pre-loading skills
* c23133a04 fix(handoff): recycle re-pick explains its move and records it on disk
* d8a5eecd3 docs(research): token-efficiency re-gate — workflow-lean PASS, slim FAIL on turns and tool errors
* f5767dadd feat(tokeff-eval): F1 re-gate data — 200 runs with the restored close contract, blind verdicts
[exit 0]
```

### `git branch -a -v`
```
* main                b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
  remotes/origin/HEAD -> origin/main
  remotes/origin/main b8dbe299a fix(claude-accounts): kernel deadline on --keepwarm so a wedged tick cannot hold the router lock
[exit 0]
```

### `git ls-remote origin 2>/dev/null || echo '(no origin)'`
```
b8dbe299a71d3916ac05a13caac98a107ec06d78	HEAD
b8dbe299a71d3916ac05a13caac98a107ec06d78	refs/heads/main
[exit 0]
```

### `git diff b8dbe299a71d3916ac05a13caac98a107ec06d78 --stat -- . ':!.claude' 2>/dev/null`
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

### Harness verifier (code)
```
truth: 40 of 41 are c10; not c10: migrations/0001-migrations-ledger-scaffold.sh 
VERIFIER: JUDGED read-only, tree untouched
```

### `git status --short`
```

[exit 0]
```
