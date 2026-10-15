#!/usr/bin/env bats
# scripts/kitty-apply-layout.py — the kitten the resume restorer (bin/cc-resume-layout.sh) fires when
# a replayed Splits tab came back with the wrong tree. It must set the tab's EXACT tree (axis, bias,
# pane order) over the panes the tab already holds, and refuse — touching nothing — when the spec
# names other panes, the tab is not in splits, or the spec cannot be read.
#
# The kitten runs here under kitty's own python (`kitty +runpy`) against kitty's REAL Splits layout
# and Pair (kitty.layout.splits), so set_layout_state, Pair.unserialize/serialize and
# layout_opts.serialized are the real ones. Only the boss/tab/window plumbing is fake: tab.relayout
# records the tree it sees on each call (kitty's do_layout needs a live OS window), and
# set_layout_state is wrapped to count calls before delegating to the real method.
# Window ids (101..) and group ids (11..) differ on purpose, so a kitten that forgets to translate
# window ids into the group ids kitty's pairs are written in cannot pass.
#
# RED-proof: at HEAD (the pre-change commit) scripts/kitty-apply-layout.py does not exist
# (`git show HEAD:scripts/kitty-apply-layout.py` → "fatal: path ... exists on disk, but not in
# 'HEAD'"); pointing the driver at that absent file, every case below fails — the driver exits 1
# with FileNotFoundError from spec_from_file_location/exec_module and prints no RESULT line, so the
# status check of each test fails (re-run by the reviewer on a scratch copy: 1..5, all 5 not ok).
# Observed 2026-10-15. Case 1 also fails for the intended reason on a scratch mutant whose window →
# group translation was removed (`return gid[x]` → `return x`): ok:false, tree unchanged.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KITTEN="$REPO/scripts/kitty-apply-layout.py"
  KITTY="$(command -v kitty 2>/dev/null || true)"
  [ -n "$KITTY" ] || KITTY=/Applications/kitty.app/Contents/MacOS/kitty
  [ -x "$KITTY" ] || skip "kitty is not installed — these tests run the kitten under kitty's own python"
  # The tab's tree before the kitten runs, in GROUP ids: (11 | 12) beside 13.
  INIT='{"one":{"one":11,"two":12},"two":13}'
}

# drive <kitten> <splits|horizontal> <spec path> [target window, 102] → one line `RESULT <json>` with:
# ret (the handler's parsed return), file (the spec's "result" path, else <spec>.result),
# default_file (whether <spec>.result exists), relayouts (tree seen at each
# tab.relayout call), sls (set_layout_state calls), tree (final tree), raised (exception, if any).
# Tab 1 holds groups 11 (window 101), 12 (windows 102 + overlay 112), 13 (window 103); tab 2 holds
# group 21 (window 201). The kitten is invoked from window 102.
drive() {
  CC_KITTEN="$1" CC_LAYOUT="$2" CC_SPEC="$3" CC_TARGET="${4:-102}" CC_INIT="$INIT" "$KITTY" +runpy '
def main():
    import os, json, importlib.util
    from kitty.layout.splits import Splits, Pair
    from kitty.layout.vertical import Horizontal
    sp = importlib.util.spec_from_file_location("k", os.environ["CC_KITTEN"])
    k = importlib.util.module_from_spec(sp); sp.loader.exec_module(k)
    class W:
        def __init__(s, wid, tab_id): s.id, s.tab_id = wid, tab_id
    class G:
        def __init__(s, gid, windows): s.id, s.windows = gid, windows
        def __iter__(s): return iter(s.windows)
    class WL:
        def __init__(s, groups): s.groups = groups
        def iter_all_layoutable_groups(s): return iter(s.groups)
    class T:
        def __init__(s, tid, layout, groups): s.id, s.current_layout, s.windows, s.snaps = tid, layout, WL(groups), []
        def relayout(s):
            lay = s.current_layout
            s.snaps.append(lay.pairs_root.serialize() if isinstance(lay, Splits) else "relayout")
    class B:
        def __init__(s, tabs, wm): s.tabs, s.window_id_map = tabs, wm
        def tab_for_id(s, tid): return s.tabs.get(tid)
    if os.environ["CC_LAYOUT"] == "splits":
        lay = Splits(1, 1)
        root = Pair(); root.unserialize(json.loads(os.environ["CC_INIT"]), lambda g: g); lay.pairs_root = root
    else:
        lay = Horizontal(1, 1)
    real = lay.set_layout_state
    calls = []
    def counted(*a, **kw):
        calls.append(1)
        return real(*a, **kw)
    lay.set_layout_state = counted
    t1 = T(1, lay, [G(11, [W(101, 1)]), G(12, [W(102, 1), W(112, 1)]), G(13, [W(103, 1)])])
    t2 = T(2, Splits(1, 2), [G(21, [W(201, 2)])])
    wm = {w.id: w for t in (t1, t2) for g in t.windows.groups for w in g.windows}
    out = {"raised": None, "ret": None}
    try:
        out["ret"] = json.loads(k.handle_result(["kitty-apply-layout.py", os.environ["CC_SPEC"]], "", int(os.environ["CC_TARGET"]), B({1: t1, 2: t2}, wm)))
    except Exception as e:
        out["raised"] = repr(e)
    try:
        rf = json.load(open(os.environ["CC_SPEC"])).get("result")
    except Exception:
        rf = None
    rf = rf or os.environ["CC_SPEC"] + ".result"
    out["file"] = json.load(open(rf)) if os.path.exists(rf) else None
    out["default_file"] = os.path.exists(os.environ["CC_SPEC"] + ".result")
    out["relayouts"], out["sls"] = t1.snaps, len(calls)
    out["tree"] = lay.pairs_root.serialize() if isinstance(lay, Splits) else None
    print("RESULT " + json.dumps(out, sort_keys=True))
main()
' 2>&1
}

# spec <name> <pairs json> → path of a spec file in the restorer's shape (result = <spec>.result)
spec() {
  local p="$BATS_TEST_TMPDIR/$1.json"
  printf '{"pairs": %s, "result": "%s.result"}\n' "$2" "$p" > "$p"
  printf '%s' "$p"
}

result_of() { printf '%s\n' "$1" | sed -n 's/^RESULT //p'; }

@test "a spec naming exactly the tab's panes sets that tree (new order, axis, bias) in group ids" {
  # Window-id spec: 103 on top (30%), then 101 beside 102 (60%) below it — every property differs.
  s="$(spec want '{"horizontal": false, "bias": 0.3, "one": 103, "two": {"bias": 0.6, "one": 101, "two": 102}}')"
  want='{"horizontal": false, "bias": 0.3, "one": 13, "two": {"bias": 0.6, "one": 11, "two": 12}}'
  run drive "$KITTEN" splits "$s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$(result_of "$output")"
  [ -n "$r" ] || { echo "$output"; false; }
  printf '%s' "$r" | jq -e '.raised == null and .ret.ok == true and .ret.tab == 1' >/dev/null || { echo "$r"; false; }
  printf '%s' "$r" | jq -e --argjson w "$want" '.tree == $w' >/dev/null || { echo "$r"; false; }
  # Laid out once before (so pairs_root holds every group) and once after, on the new tree.
  printf '%s' "$r" | jq -e --argjson w "$want" --argjson i "$INIT" '.relayouts == [$i, $w] and .sls == 1' >/dev/null || { echo "$r"; false; }
  printf '%s' "$r" | jq -e '.file == .ret' >/dev/null || { echo "$r"; false; }
}

@test "a spec that omits a pane, or names a pane of another tab, is refused and changes nothing" {
  omit="$(spec omit '{"one": 101, "two": 102}')"
  # Three leaves, so only the kitten's own "not in this tab" branch can refuse it, not the set check.
  foreign="$(spec foreign '{"one": {"one": 101, "two": 102}, "two": 201}')"
  for s in "$omit" "$foreign"; do
    run drive "$KITTEN" splits "$s"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    r="$(result_of "$output")"
    [ -n "$r" ] || { echo "$output"; false; }
    printf '%s' "$r" | jq -e '.raised == null and .ret.ok == false and (.ret.why | length > 0)' >/dev/null || { echo "$s: $r"; false; }
    printf '%s' "$r" | jq -e --argjson i "$INIT" '.sls == 0 and .relayouts == [] and .tree == $i' >/dev/null || { echo "$s: $r"; false; }
    printf '%s' "$r" | jq -e '.file == .ret' >/dev/null || { echo "$s: $r"; false; }
  done
  run drive "$KITTEN" splits "$foreign"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  result_of "$output" | jq -e '.ret.tab == 1 and (.ret | has("have") | not)' >/dev/null || { echo "$output"; false; }
  # The omission names the difference: the tab's groups against the spec's.
  run drive "$KITTEN" splits "$omit"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  result_of "$output" | jq -e '.ret.have == [11, 12, 13] and .ret.want == [11, 12]' >/dev/null || { echo "$output"; false; }
}

@test "a tab not in splits is refused untouched (kitty's base set_layout_state would say yes)" {
  s="$(spec horiz '{"horizontal": false, "one": 103, "two": {"one": 101, "two": 102}}')"
  run drive "$KITTEN" horizontal "$s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$(result_of "$output")"
  [ -n "$r" ] || { echo "$output"; false; }
  printf '%s' "$r" | jq -e '.raised == null and .ret.ok == false and (.ret.why | length > 0)' >/dev/null || { echo "$r"; false; }
  printf '%s' "$r" | jq -e '.sls == 0 and .relayouts == [] and .file == .ret' >/dev/null || { echo "$r"; false; }
}

@test "an unreadable spec (missing, or not JSON) answers ok:false without raising" {
  bad="$BATS_TEST_TMPDIR/bad.json"; printf '{"pairs": ' > "$bad"
  for s in "$BATS_TEST_TMPDIR/absent.json" "$bad"; do
    run drive "$KITTEN" splits "$s"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    r="$(result_of "$output")"
    [ -n "$r" ] || { echo "$output"; false; }
    printf '%s' "$r" | jq -e '.raised == null and .ret.ok == false and (.ret.why | length > 0)' >/dev/null || { echo "$s: $r"; false; }
    printf '%s' "$r" | jq -e --argjson i "$INIT" '.sls == 0 and .relayouts == [] and .tree == $i' >/dev/null || { echo "$s: $r"; false; }
    # The restorer reads <spec>.result; with no readable spec that is the only place left to answer.
    printf '%s' "$r" | jq -e '.file == .ret' >/dev/null || { echo "$s: $r"; false; }
  done
}

@test "the answer goes to the spec's own result path when it names one" {
  p="$BATS_TEST_TMPDIR/own.json"
  printf '{"pairs": {"one": {"one": 101, "two": 102}, "two": 103}, "result": "%s.out"}\n' "$p" > "$p"
  run drive "$KITTEN" splits "$p"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$(result_of "$output")"
  [ -n "$r" ] || { echo "$output"; false; }
  printf '%s' "$r" | jq -e '.ret.ok == true and .file == .ret and .default_file == false' >/dev/null || { echo "$r"; false; }
}

@test "a target pane that is gone (closed after kitty @ ls) answers ok:false and touches nothing" {
  s="$(spec gone '{"one": {"one": 101, "two": 102}, "two": 103}')"
  run drive "$KITTEN" splits "$s" 999
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$(result_of "$output")"
  [ -n "$r" ] || { echo "$output"; false; }
  printf '%s' "$r" | jq -e --argjson i "$INIT" '.raised == null and .ret.ok == false and (.ret.why | length > 0) and .sls == 0 and .relayouts == [] and .tree == $i and .file == .ret' >/dev/null || { echo "$r"; false; }
}
