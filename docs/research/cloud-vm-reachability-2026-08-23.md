# Cloud VM reachability — 2026-08-23

This container can reach exactly one git repository — `claude-infrastructure`, cloned shallow at
`/home/user/claude-infrastructure` from `https://github.com/renchris/claude-infrastructure` — and
cannot reach the operator's `~/Development` tree or any sibling checkout, because neither exists on
this filesystem.

```
git remote -v
origin	https://github.com/renchris/claude-infrastructure (fetch)
origin	https://github.com/renchris/claude-infrastructure (push)
```

```
git rev-parse --is-shallow-repository
true
```

```
git rev-list --count HEAD
50
```

```
ls ~/Development 2>&1 || echo "no ~/Development"
ls: cannot access '/root/Development': No such file or directory
no ~/Development
```

```
ls ..
claude-infrastructure
```

```
pwd
/home/user/claude-infrastructure
```

```
git branch --show-current
claude/fire-20260823T212516Z-9432-1
```

## WHAT THIS CONFIRMS

No. No repository other than `claude-infrastructure` is present in this container.
Evidence: `ls ..` returns the single entry `claude-infrastructure`, so the parent of the checkout
holds no sibling clone; `ls ~/Development` fails with `No such file or directory` (HOME is `/root`,
not the operator's machine), so the multi-repo development tree is absent entirely.
The `cc-eligible` reach arm's premise holds from inside: an item whose project is not the attached
repo has nothing to run against here.
