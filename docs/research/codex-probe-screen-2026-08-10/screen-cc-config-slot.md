VERDICT: DEFECTIVE

EVIDENCE:

1. `desharing_enabled()` — line 91 (guard enumerating spellings, not the class it names)
   `    except (OSError, json.JSONDecodeError, AttributeError):`
   The docstring one line above promises the CLASS: "a missing, unreadable, or malformed flag file
   means DISABLED"; the handler enumerates three spellings and misses the sibling of
   `json.JSONDecodeError` under `ValueError` — `UnicodeDecodeError`, raised by `json.load(fh)` on a
   non-UTF-8 (truncated/corrupt/binary) flag file. Reproduced against origin/main's file:
     `CC_CONFIG_SLOT_FLAG_FILE=assets/demo/kitty-panes.webp bin/cc-config-slot next`
     -> `UnicodeDecodeError: 'utf-8' codec can't decode byte 0x8e in position 5`, traceback, rc=1
   i.e. the guard whose own docstring says it "sits in the launch path of every session" does not
   fail closed to DISABLED on a malformed flag — it aborts the resolver. `except (OSError, ValueError,
   AttributeError)` is the class. The author already reached for the exotic `AttributeError` (non-dict
   JSON top level), so this is a missed spelling in an attempted-exhaustive list, not an out-of-scope
   input.

2. `main()` — lines 171-174 (a hit reported as a miss; error class read as absence)
   `    except KeyError:`
   `        known = "|".join(sorted(load_accounts()))`
   `        print(f"cc-config-slot: unknown account: {acct} ({known})", file=sys.stderr)`
   `resolve()` raises `KeyError` from two other places besides the deliberate `raise KeyError(acct)`
   at line 108: `rec["config_dir"]` (line 109) and `a["name"]` inside `load_accounts()` (line 78).
   A record that IS present but malformed is therefore reported as absent. Reproduced by substituting
   a record `{'next': {'name': 'next'}}`:
     `cc-config-slot: unknown account: next (next)`  -> exit 2
   The message names `next` as unknown while simultaneously listing `next` as known — a self-refuting
   diagnostic that sends the operator to accounts.json's name list instead of its missing field, and
   returns 2 ("unknown account") where the documented code is 1 ("error"). Secondary to (1) in
   severity, but the same shape: a lookup that hit is scored as a miss.

Non-defects probed and cleared (so the two above are not padding):
   - `_accounts_json_path()` (line 71) uses `abspath`, not `realpath`. Under install.sh:637 every
     `bin/cc-*` is a PER-FILE SYMLINK into ~/.claude/bin, and `abspath` deliberately does NOT resolve
     it, so the root computes to ~/.claude — where install.sh:444 symlinks accounts.json. Correct in
     both the checkout and the deployed layer; it also dodges scripts/self-path-lint.sh (Python, and
     the guarded/`..`-traversal rule is a shell ratchet).
   - The OFF path's "byte-identical to what the launchers already export" claim (lines 31-34, 112)
     holds: `os.path.expanduser(rec["config_dir"])` matches bin/claude-accounts:223, which expands the
     same tilde field on load before exporting it at :543.
   - `slot_for_class()` sum-mod-3 is a weak hash but its stated contract ("same class -> same slot")
     is exactly what it delivers; collisions are inherent to 3 slots, not to the hash, and the file
     concedes the residual sharing itself (lines 41-45, "falls roughly with the SQUARE").
   - Arg parsing: `--class` at end -> rc 2; leading-dash acct -> rc 2; no args -> rc 2 while `--help`
     -> rc 0; `--status` short-circuits before the account is required. No vacuous pass.

OPEN_FINDINGS: none found; searched docs/research/ and docs/plans/ (plus docs/runbooks/) for
"cc-config-slot", "de-sharing", "desharing". Hits are status/gating only — RELOGIN_ACTIVATION.md:28,
56, 151; RELOGIN_AUTOMATION_PLAN.md:325; RELOGIN_BUILD_CONTRACT.md:556 ("built behind a flag, inert by
default, not activated, gated on E1"); backlog-consolidation-2026-08-09/OUT-accounts.md:22,78 (the E1
decision still open). None names a defect in this file. Note RELOGIN_ACTIVATION.md:151 asserts "20
tests pin exactly this" against tests/cc-config-slot.bats — an exact-count doc claim, but it lives in
the runbook, not in the candidate.
