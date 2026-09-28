#!/usr/bin/env bats
# cc-upgrade-skill — structural contract of skills/cc-upgrade/ (the router + lane files that replaced
# model-upgrade, cc-version-audit and cc-upgrade-gate on 2026-09-28).
#
# What each case protects, and the regression it catches:
#   1. closure: every lane file the router names exists, every lane file is named by the router,
#      and lane files carry no frontmatter (a sibling with frontmatter never loads, and a file the
#      router does not name is a rule nobody reads);
#   2. no perishable facts outside holds.md: versioned binary dirs, CC version numbers and the
#      deleted launcher/script names are how the three old skills rotted; a line that genuinely
#      needs one says "historical";
#   3. gate.md's check count and table match lib/cc-upgrade-gate/check*.sh (the old skill said
#      "14 checks" for months after #15 landed);
#   4. the router fits the post-compaction re-attach budget (5,000 tokens; 16,000 chars at ~4/token);
#   5. the three old names are model-invisible alias stubs that forward to cc-upgrade;
#   6. mutation control: each check goes red on a scratch copy with one injected defect.
#
# RED-proof: case 6 is the red-proof — every check is shown red on an injected defect and green on
# the unmodified copy. Against the pre-consolidation tree (skills/cc-upgrade absent) cases 1-5 fail.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# --- checks, each over a root dir so case 6 can run them on a scratch copy -----------------------

check_closure() {  # <root>
  local d="$1/skills/cc-upgrade" f named rc=0
  [ -f "$d/SKILL.md" ] || { echo "no router"; return 1; }
  named="$(grep -oE '\b[a-z]+\.md\b' "$d/SKILL.md" | grep -vx 'SKILL.md\|UPGRADE.md' | sort -u)"
  for f in $named; do
    [ -f "$d/$f" ] || { echo "router names missing file: $f"; rc=1; }
  done
  for f in "$d"/*.md; do
    f="${f##*/}"; [ "$f" = SKILL.md ] && continue
    printf '%s\n' "$named" | grep -qx "$f" || { echo "lane file not named by the router: $f"; rc=1; }
    [ "$(head -1 "$d/$f")" != "---" ] || { echo "lane file has frontmatter: $f"; rc=1; }
  done
  return "$rc"
}

check_perishable() {  # <root>
  local hits
  hits="$(cd "$1/skills" && grep -nE '\.claude-[0-9]{3}|2\.1\.[0-9]{3}|claude-next|cc-next|10-opus5' \
            cc-upgrade/*.md cc-upgrade-gate/SKILL.md model-upgrade/SKILL.md cc-version-audit/SKILL.md \
          | grep -v '^cc-upgrade/holds\.md:' | grep -vi 'historical' || true)"
  [ -z "$hits" ] || { printf 'perishable fact outside holds.md:\n%s\n' "$hits"; return 1; }
}

check_gate_count() {  # <root>
  local g="$1/skills/cc-upgrade/gate.md" files heading rows
  files="$(find "$1/lib/cc-upgrade-gate" -maxdepth 1 -name 'check[0-9]*.sh' | sed -E 's|.*/check0*([0-9]+)_.*|\1|' | sort -n | tr '\n' ' ')"
  heading="$(sed -nE 's/^## The ([0-9]+) checks$/\1/p' "$g")"
  rows="$(grep -oE '^\| *[0-9]+ *\|' "$g" | tr -dc '0-9\n' | sort -n | tr '\n' ' ')"
  [ -n "$files" ] || { echo "no check files found"; return 1; }
  [ "$heading" = "$(printf '%s' "$files" | wc -w | tr -d ' ')" ] || { echo "heading says '$heading', files: $files"; return 1; }
  [ "$rows" = "$files" ] || { echo "table rows [$rows] != check files [$files]"; return 1; }
}

check_router_size() {  # <root>
  local n; n="$(wc -c <"$1/skills/cc-upgrade/SKILL.md" | tr -d ' ')"
  [ "$n" -le 16000 ] || { echo "router is $n chars > 16000"; return 1; }
}

check_stubs() {  # <root>
  local s f rc=0
  for s in cc-upgrade-gate model-upgrade cc-version-audit; do
    f="$1/skills/$s/SKILL.md"
    [ -f "$f" ] || { echo "$s: stub missing"; rc=1; continue; }
    grep -qx "name: $s" "$f" || { echo "$s: name mismatch"; rc=1; }
    grep -qx 'disable-model-invocation: true' "$f" || { echo "$s: model-invocable"; rc=1; }
    # shellcheck disable=SC2016  # the backticks are literal markdown text, not a substitution
    grep -q '`cc-upgrade`' "$f" || { echo "$s: does not forward to cc-upgrade"; rc=1; }
  done
  return "$rc"
}

@test "1: the router and its lane files are a closed set" {
  run check_closure "$REPO"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "2: no versioned dir, CC version or deleted launcher name outside holds.md" {
  run check_perishable "$REPO"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "3: gate.md's check count and table match lib/cc-upgrade-gate/check*.sh" {
  run check_gate_count "$REPO"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "4: the router fits the 5,000-token compaction re-attach budget" {
  run check_router_size "$REPO"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "5: the three old names are model-invisible stubs that forward to cc-upgrade" {
  run check_stubs "$REPO"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "6: mutation control: each check goes red on one injected defect and green without it" {
  S="$BATS_TEST_TMPDIR/s"
  fresh() { rm -rf "$S"; mkdir -p "$S/lib"; cp -Rp "$REPO/skills" "$S/"; cp -Rp "$REPO/lib/cc-upgrade-gate" "$S/lib/"; }
  fresh
  check_closure "$S"; check_perishable "$S"; check_gate_count "$S"; check_router_size "$S"; check_stubs "$S"

  printf 'orphan\n' >"$S/skills/cc-upgrade/orphan.md"
  run check_closure "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"not named by the router: orphan.md"* ]] || false
  fresh; rm "$S/skills/cc-upgrade/keying.md"
  run check_closure "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"router names missing file: keying.md"* ]] || false

  fresh; printf 'run ~/.claude-280/node_modules/.bin/claude\n' >>"$S/skills/cc-upgrade/gate.md"
  run check_perishable "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"cc-upgrade/gate.md:"* ]] || false
  fresh; printf 'launch it with cc-next\n' >>"$S/skills/model-upgrade/SKILL.md"
  run check_perishable "$S"; [ "$status" -eq 1 ]
  fresh; printf 'pinned at 2.1.284 (historical)\n' >>"$S/skills/cc-upgrade/gate.md"
  check_perishable "$S"   # a tagged historical line stays legal

  fresh; cp "$S/lib/cc-upgrade-gate/check15_depth_effect.sh" "$S/lib/cc-upgrade-gate/check16_new.sh"
  run check_gate_count "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"heading says '15'"* ]] || false
  fresh; sed -i.bak '/^| 15 |/d' "$S/skills/cc-upgrade/gate.md"
  run check_gate_count "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"table rows"* ]] || false

  fresh; python3 -c "print('x' * 16001)" >>"$S/skills/cc-upgrade/SKILL.md"
  run check_router_size "$S"; [ "$status" -eq 1 ]

  fresh; sed -i.bak '/^disable-model-invocation/d' "$S/skills/cc-version-audit/SKILL.md"
  run check_stubs "$S"; [ "$status" -eq 1 ]; [[ "$output" == *"cc-version-audit: model-invocable"* ]] || false
}
