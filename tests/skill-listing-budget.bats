#!/usr/bin/env bats
# skill-listing-budget — regression guard for item F7 of docs/research/token-efficiency-2026-09-23.
#
# Claude Code renders every skill and command description into a listing capped at 30,000 chars
# (1% of a 1M window x 3 bytes/token). Before F7 our own entries wanted ~48k, so the renderer kept
# about 30 of them name-only, and a name-only skill cannot be matched by its description
# (docs/research/token-efficiency-2026-09-23/measure/listings.md §1-§2). F7 cut the listing to
# ~22.9k with every entry described. Nothing else stops the descriptions growing back, so this
# suite pins what F7 established:
#   1. every listed skill/command has a description, at most 250 chars (150 for the six commands
#      whose one-liner was written from their body);
#   2. every frontmatter parses as strict YAML (8 did not before F7; listings.md §2);
#   3. the three research agents keep their descriptions at most 300 chars;
#   4. the repo-owned share of the listing stays under a headroom line;
#   5. a mutation control: each check goes red on a scratch copy with one defect injected, and
#      stays green on the unmodified copy, so a green run above is evidence and not a dead check.
# The before/after numbers come from docs/research/token-efficiency-2026-09-23/scripts/listings_f7_verify.py.
#
# RED-proof: LISTING_ROOT=<a `git archive` export of the pre-F7 tree> bats tests/skill-listing-budget.bats
# fails all five cases (5 because its unmodified copy is already red); measured 2026-09-23 against the
# pre-F7 commit fd5be8340. Hermetic: reads only files under LISTING_ROOT (default: this checkout).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${LISTING_ROOT:-$REPO_ROOT}"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  CHECK="$BATS_TEST_TMPDIR/check.py"
  cat >"$CHECK" <<'PY'
import glob, json, os, re, sys
root, mode = sys.argv[1], sys.argv[2]
try:
    import yaml
except ImportError:
    yaml = None
if mode == "has-yaml":
    sys.exit(0 if yaml else 1)

DESC_MAX, BODY_DERIVED_MAX, AGENT_MAX, ENTRY_CAP = 250, 150, 300, 1536
# Commands that had no frontmatter before F7; their one-liner was written from the body.
BODY_DERIVED = {"deploy-check", "fix-lint", "pr", "review", "scaffold", "ship"}
# Per-entry exceptions to DESC_MAX, each pinned at its length so it cannot grow. Empty today.
OVERRIDES = {}
AGENTS = ("deep-research", "deep-research-sonnet", "frontier-derivation")
# Repo-owned entries rendered 13.4k of the 22.9k listing after F7. Bundled and live-only skills
# take ~9.5k, so 15,000 leaves room for about six new skills at the 250 limit under the 30,000 budget.
REPO_TOTAL_MAX = 15000

def fallback(fm):
    # Line parser for when PyYAML is absent: key: value, quoted scalars, and >/| block scalars.
    meta, lines, i = {}, fm.splitlines(), 0
    while i < len(lines):
        m = re.match(r"^([A-Za-z_][\w-]*):\s?(.*)$", lines[i]); i += 1
        if not m:
            continue
        v = m.group(2).strip()
        if v[:1] in (">", "|"):
            parts = []
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or not lines[i].strip()):
                parts.append(lines[i].strip()); i += 1
            v = " ".join(p for p in parts if p)
        elif len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1].replace('\\"', '"') if v[0] == '"' else v[1:-1].replace("''", "'")
        meta[m.group(1)] = v
    return meta

def parse(p):
    t = open(p, encoding="utf-8").read()
    m = re.match(r"^---[ \t]*\n(.*?)\n---[ \t]*\n", t, re.S)
    if not m:
        return {}, True
    if yaml:
        try:
            return (yaml.safe_load(m.group(1)) or {}), True
        except Exception:
            return fallback(m.group(1)), False
    return fallback(m.group(1)), True

entries = {}
for p in sorted(glob.glob(os.path.join(root, "skills/*/SKILL.md"))):
    entries[os.path.basename(os.path.dirname(p))] = p
for p in sorted(glob.glob(os.path.join(root, "commands/*.md"))):
    n = os.path.basename(p)[:-3]
    if re.search(r"^disable-model-invocation:\s*true\s*$", open(p, encoding="utf-8").read(), re.M):
        continue  # not listed
    entries.setdefault(n, p)  # a skill shadows the same-named command

bad, total = [], 0
for n, p in entries.items():
    meta, strict = parse(p)
    d = str(meta.get("description") or "")
    w = str(meta.get("when_to_use") or "")
    if mode == "lengths":
        lim = OVERRIDES.get(n, BODY_DERIVED_MAX if n in BODY_DERIVED else DESC_MAX)
        if not d:
            bad.append(f"{n}: no description")
        elif len(d) > lim:
            bad.append(f"{n}: description {len(d)} chars > {lim}")
    elif mode == "yaml" and not strict:
        bad.append(f"{n}: frontmatter is not strict YAML")
    rendered = d + (" - " + w if w else "")
    total += len(n) + 4 + min(len(rendered), ENTRY_CAP) + 1 if rendered else len(n) + 3

if mode == "agents":
    for a in AGENTS:
        meta, strict = parse(os.path.join(root, "agents", a + ".md"))
        d = str(meta.get("description") or "")
        if not d or len(d) > AGENT_MAX:
            bad.append(f"{a}: agent description {len(d)} chars (want 1..{AGENT_MAX})")
elif mode == "total":
    print(f"repo-owned listing chars: {total} over {len(entries)} entries (max {REPO_TOTAL_MAX})")
    if total > REPO_TOTAL_MAX:
        bad.append(f"repo-owned listing {total} chars > {REPO_TOTAL_MAX}")
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
}

check() { python3 "$CHECK" "$1" "$2"; }

@test "1: every listed skill and command has a description within its length limit" {
  run check "$ROOT" lengths
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "2: every skill and command frontmatter parses as strict YAML" {
  check "$ROOT" has-yaml || skip "PyYAML not installed; strict parsing cannot be checked here"
  run check "$ROOT" yaml
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "3: the three research agents keep descriptions at most 300 chars" {
  run check "$ROOT" agents
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "4: the repo-owned share of the listing stays under its headroom line" {
  run check "$ROOT" total
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "5: mutation control: each check goes red on one injected defect and green without it" {
  S="$BATS_TEST_TMPDIR/scratch"; mkdir -p "$S"
  cp -Rp "$ROOT/skills" "$ROOT/commands" "$ROOT/agents" "$S/"
  fresh() { rm -rf "$S"; mkdir -p "$S"; cp -Rp "$ROOT/skills" "$ROOT/commands" "$ROOT/agents" "$S/"; }
  setdesc() {  # setdesc <file> <new description line>
    python3 - "$1" "$2" <<'PY'
import re, sys
p, line = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
t, n = re.subn(r"^description:.*$", lambda m: line, t, count=1, flags=re.M)
assert n == 1, p
open(p, "w", encoding="utf-8").write(t)
PY
  }
  long() { python3 -c "import sys; print('x' * int(sys.argv[1]))" "$1"; }

  # The unmodified copy is green on every mode, so each red below is the injected defect's.
  for m in lengths agents total; do check "$S" "$m"; done
  if check "$S" has-yaml; then check "$S" yaml; fi

  setdesc "$S/skills/plan-conventions/SKILL.md" "description: \"$(long 251)\""
  run check "$S" lengths
  [ "$status" -eq 1 ]; [[ "$output" == *"plan-conventions: description 251 chars > 250"* ]] || false

  fresh; setdesc "$S/commands/ship.md" "description: \"$(long 151)\""
  run check "$S" lengths
  [ "$status" -eq 1 ]; [[ "$output" == *"ship: description 151 chars > 150"* ]] || false

  fresh; setdesc "$S/skills/plan-conventions/SKILL.md" "description: \"\""
  run check "$S" lengths
  [ "$status" -eq 1 ]; [[ "$output" == *"plan-conventions: no description"* ]] || false

  fresh; setdesc "$S/agents/deep-research.md" "description: \"$(long 301)\""
  run check "$S" agents
  [ "$status" -eq 1 ]; [[ "$output" == *"deep-research: agent description 301 chars"* ]] || false

  fresh
  for i in 1 2 3 4 5 6 7 8 9 10; do  # ten new skills at the 250 limit cross the headroom line
    mkdir -p "$S/skills/new-skill-$i"
    printf -- '---\nname: new-skill-%s\ndescription: "%s"\n---\nbody\n' "$i" "$(long 250)" >"$S/skills/new-skill-$i/SKILL.md"
  done
  run check "$S" lengths
  [ "$status" -eq 0 ]
  run check "$S" total
  [ "$status" -eq 1 ]; [[ "$output" == *"repo-owned listing "*" > 15000"* ]] || false

  if check "$S" has-yaml; then
    fresh; setdesc "$S/skills/plan-conventions/SKILL.md" "description: Use when: a plan is edited"
    run check "$S" yaml
    [ "$status" -eq 1 ]; [[ "$output" == *"plan-conventions: frontmatter is not strict YAML"* ]] || false
  fi
}
