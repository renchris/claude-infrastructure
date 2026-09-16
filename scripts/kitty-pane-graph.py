#!/usr/bin/env python3
# ============================================================================
#  kitty-pane-graph.py — THE VERDICT READER for wave W4 (KITTY_DRAG_ACTION.md
#  § W4 point 4).  It answers ONE question — *did the pane layout actually
#  change, and is that change a REORDER?* — and it answers it with a word, not
#  with data for a human to interpret.
#
#  ── 🚨 THE WITNESS RULE — WHY THIS FILE EXISTS AND WHY ITS ORDER IS FIXED ──
#  (memory: `witness-must-test-the-set-before-the-order`, plan § W4.)
#
#  W4 is the one wave whose evidence a session may NOT manufacture: it is a
#  HUMAN ACTION.  This tool is what converts that action into a checkable fact,
#  so its failure mode is fabricating the single piece of evidence nobody else
#  can check, in the direction the session is under pressure to produce.
#
#  CLOSING A PANE MAKES ITS TWO NEIGHBOURS ADJACENT.  A differ that tests
#  "did any surviving member's adjacency change?" BEFORE it tests "is the
#  member set the same?" therefore reports ordinary churn — one pane closing —
#  as a REORDER.  Measured last session: 10 such events in the first hours
#  across 11-13 live panes, every one of which the first version reported as
#  REORDERED.
#
#  ⇒ THEREFORE, AND THIS ORDER IS LOAD BEARING:
#       (1) test `gone or new` FIRST.  A changed member set ends the comparison
#           with SET-CHANGED and an instruction to re-baseline.
#       (2) ONLY a change among members present on BOTH sides may be called
#           REORDERED.
#  A stable member set is a PRECONDITION of the verdict word, not a detail.
#  `diff_graphs()` below marks that ordering with a 🚨 banner; moving the
#  order test above the set test is the MUTANT that tests/kitty-pane-graph.bats
#  branch (b) exists to kill.
#
#  ── THE REAL `neighbors` SCHEMA — MEASURED, NOT GUESSED ───────────────────
#  Read off a SANDBOX kitty (own KITTY_CONFIG_DIRECTORY, socket outside the
#  /tmp/kitty-* glob, all three KITTY_ vars dropped), 2026-09-16, against
#  /Applications/kitty.app/Contents/MacOS/kitty (the operator's shipped
#  0.48.2).  The command and its literal output:
#
#    $ kitten @ --to unix:/tmp/kdwp.sock ls        # 3 panes, layout=splits
#      id 1 neighbors = {'bottom': [2, 3]}
#      id 2 neighbors = {'right': [3], 'top': [1]}
#      id 3 neighbors = {'left': [2], 'top': [1]}
#
#  So:  window['neighbors'] is a DICT.  Keys are drawn from
#       {'left','right','top','bottom'} and a direction with no neighbour is
#       ABSENT, not present-and-empty.  Each value is a LIST of int window ids
#       and it can hold MORE THAN ONE id (pane 1 above).  Any parser that
#       assumes a scalar, or that assumes all four keys exist, is wrong on
#       real data — that is branch (e) of the control suite.
#
#  The enclosing shape of `kitten @ ls` is a LIST of OS windows; each has
#  'id' and 'tabs'; each tab has 'id', 'layout' and 'windows'; each window
#  carries 'id' and 'neighbors' among 24 keys (measured list in the same run:
#  at_prompt cmdline columns created_at cwd env foreground_processes
#  has_activity_since_last_focus id in_alternate_screen is_active is_focused
#  is_self last_cmd_exit_status last_focused_at last_reported_cmdline lines
#  needs_attention neighbors pid session_name title title_overridden
#  user_vars).
#
#  ── WHAT IS AND IS NOT PART OF A MEMBER'S STATE ───────────────────────────
#  A member is keyed on its WINDOW ID, which is stable across a move.  Its
#  compared state is (os_window_id, tab_id, normalised neighbours).  Two
#  deliberate exclusions:
#    * `columns`/`lines` are NOT compared — a terminal resize is not a layout
#      change, and including them would make every verdict a false REORDERED.
#    * the ORDER of ids inside one direction's list is normalised away
#      (sorted), because the directional keys already carry the placement:
#      when two panes swap, their own left/right keys flip.  Comparing raw
#      list order would add false positives without adding a signal.
#  Keying on the window id rather than on (tab, id) is also deliberate: a pane
#  dragged to another TAB keeps its id, so that move reads as REORDERED (a
#  layout change among a stable set), which is what it is — not as a set change.
#
#  ── USAGE ────────────────────────────────────────────────────────────────
#    kitty-pane-graph.py snapshot [--ls FILE|-] [--out FILE]
#        Normalise a `kitten @ ls` JSON document into a graph snapshot.
#
#    kitty-pane-graph.py diff BEFORE AFTER [--expect WORD] [--json]
#        Compare two documents.  Either may be a raw `ls` dump or an already
#        normalised snapshot; the shape is detected, never assumed.
#
#  Output always carries a machine-readable token on its own line:
#        verdict=NO-CHANGE | verdict=REORDERED | verdict=SET-CHANGED
#  (memory: `claimed-outcome-vs-checked-outcome` — emit a parseable verdict
#  token rather than prose a caller has to pattern-match.)
#
#  Exit codes:  0 = the comparison ran and its verdict is reported
#               1 = --expect was given and the verdict did not match it
#               2 = usage / parse error (a NON-VERDICT, never a quiet pass)
#  A parse failure is a verdict about the INSTRUMENT and exits 2 loudly; it is
#  never folded into NO-CHANGE (memory: `parse-failures-are-verdicts-not-noise`).
# ============================================================================

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

SCHEMA = 'kitty-pane-graph/1'
DIRECTIONS = ('left', 'right', 'top', 'bottom')

VERDICT_NO_CHANGE = 'NO-CHANGE'
VERDICT_REORDERED = 'REORDERED'
VERDICT_SET_CHANGED = 'SET-CHANGED'


class GraphError(Exception):
    """A fault in the INSTRUMENT or its input — never a layout verdict."""


# ---------------------------------------------------------------------------
#  Normalisation
# ---------------------------------------------------------------------------

def _normalise_neighbors(raw: Any, wid: Any) -> dict[str, list[int]]:
    """Turn one window's `neighbors` value into a canonical dict.

    Real shape (measured, see header): {'bottom': [2, 3]} — absent keys mean
    "no neighbour in that direction", and a value is a LIST that may hold more
    than one id.  Tolerated inputs: a missing/None value (treated as none), and
    a bare int where a list was expected (normalised to a 1-element list) so a
    hand-written fixture cannot silently mean something else.
    """
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise GraphError(
            f'window {wid}: neighbors is {type(raw).__name__}, expected an object; '
            f'got {raw!r}')
    out: dict[str, list[int]] = {}
    for direction, value in raw.items():
        if direction not in DIRECTIONS:
            raise GraphError(
                f'window {wid}: unknown neighbors direction {direction!r}; '
                f'expected one of {DIRECTIONS}')
        if value is None:
            continue
        if isinstance(value, int) and not isinstance(value, bool):
            ids = [value]
        elif isinstance(value, (list, tuple)):
            ids = list(value)
        else:
            raise GraphError(
                f'window {wid}: neighbors[{direction!r}] is '
                f'{type(value).__name__}, expected a list of window ids')
        clean: list[int] = []
        for n in ids:
            if isinstance(n, bool) or not isinstance(n, int):
                raise GraphError(
                    f'window {wid}: neighbors[{direction!r}] holds {n!r}, '
                    f'expected an int window id')
            clean.append(n)
        if not clean:
            # An explicitly empty list means the same as an absent key; drop it
            # so two documents spelling "no neighbour" differently compare equal.
            continue
        out[direction] = sorted(clean)
    return out


def snapshot_from_ls(doc: Any) -> dict[str, Any]:
    """Normalise a `kitten @ ls` document into a graph snapshot."""
    if not isinstance(doc, list):
        raise GraphError(
            f'`kitten @ ls` output must be a list of OS windows, got '
            f'{type(doc).__name__}')
    members: dict[str, Any] = {}
    for osw in doc:
        if not isinstance(osw, dict):
            raise GraphError(f'OS window entry is {type(osw).__name__}, expected an object')
        osw_id = osw.get('id')
        for tab in osw.get('tabs') or []:
            if not isinstance(tab, dict):
                raise GraphError(f'tab entry is {type(tab).__name__}, expected an object')
            tab_id = tab.get('id')
            for w in tab.get('windows') or []:
                if not isinstance(w, dict):
                    raise GraphError(f'window entry is {type(w).__name__}, expected an object')
                if 'id' not in w:
                    raise GraphError('a window entry carries no "id" key')
                wid = w['id']
                key = str(wid)
                if key in members:
                    raise GraphError(
                        f'window id {wid} appears twice in one `ls` document; '
                        f'the id is supposed to be unique and is the member key')
                members[key] = {
                    'osw': osw_id,
                    'tab': tab_id,
                    'n': _normalise_neighbors(w.get('neighbors'), wid),
                }
    return {'schema': SCHEMA, 'members': members}


def coerce_snapshot(doc: Any) -> dict[str, Any]:
    """Accept either a raw `ls` dump or an already-normalised snapshot.

    The shape is DETECTED, never assumed: a snapshot is an object carrying our
    schema tag; anything else must be an `ls` list.  An object that is neither
    is an instrument fault and raises rather than being coerced.
    """
    if isinstance(doc, dict):
        if doc.get('schema') != SCHEMA:
            raise GraphError(
                f'object input is not a {SCHEMA} snapshot (schema='
                f'{doc.get("schema")!r}) and is not a `kitten @ ls` list')
        members = doc.get('members')
        if not isinstance(members, dict):
            raise GraphError('snapshot "members" is missing or is not an object')
        out: dict[str, Any] = {}
        for key, m in members.items():
            if not isinstance(m, dict):
                raise GraphError(f'snapshot member {key!r} is not an object')
            out[str(key)] = {
                'osw': m.get('osw'),
                'tab': m.get('tab'),
                'n': _normalise_neighbors(m.get('n'), key),
            }
        return {'schema': SCHEMA, 'members': out}
    return snapshot_from_ls(doc)


# ---------------------------------------------------------------------------
#  The differ
# ---------------------------------------------------------------------------

def diff_graphs(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    """Compare two snapshots and return a verdict record.

    🚨 THE ORDER OF THE TWO TESTS BELOW IS THE WHOLE POINT OF THIS FILE.
    ================================================================
    STEP 1 — THE SET TEST.  Members that are gone or new.
    STEP 2 — THE ORDER TEST.  Adjacency among members present on BOTH sides.

    STEP 1 MUST COME FIRST AND MUST RETURN.  Closing a pane makes its two
    neighbours adjacent, so a surviving member's adjacency changes as a direct
    consequence of the set changing.  Running STEP 2 first therefore reports
    an ordinary pane close as REORDERED — the exact false witness this tool
    exists to prevent.  Branch (b) of tests/kitty-pane-graph.bats is the
    control that kills that mutant; do not reorder these blocks.
    ================================================================
    """
    b = before['members']
    a = after['members']

    # ----- STEP 1: THE SET TEST.  Runs first.  Returns. -------------------
    gone = sorted(set(b) - set(a), key=_idkey)
    new = sorted(set(a) - set(b), key=_idkey)
    if gone or new:
        return {
            'verdict': VERDICT_SET_CHANGED,
            'gone': gone,
            'new': new,
            'moved': [],
            'before_count': len(b),
            'after_count': len(a),
            'reason': (
                'the pane SET changed, so no adjacency difference among the '
                'survivors can be attributed to a move — closing a pane makes '
                'its two neighbours adjacent by itself. Re-baseline and repeat '
                'the gesture.'),
        }

    # ----- STEP 2: THE ORDER TEST.  Only reachable on a stable set. -------
    moved = []
    for key in sorted(b, key=_idkey):
        if b[key] != a[key]:
            moved.append({'id': key, 'before': b[key], 'after': a[key]})

    if moved:
        return {
            'verdict': VERDICT_REORDERED,
            'gone': [],
            'new': [],
            'moved': moved,
            'before_count': len(b),
            'after_count': len(a),
            'reason': (
                'the pane set is IDENTICAL on both sides and the adjacency '
                'graph changed, so the layout was genuinely rearranged.'),
        }

    return {
        'verdict': VERDICT_NO_CHANGE,
        'gone': [],
        'new': [],
        'moved': [],
        'before_count': len(b),
        'after_count': len(a),
        'reason': 'same pane set, same adjacency graph — nothing moved.',
    }


def _idkey(k: str) -> tuple[int, str]:
    try:
        return (0, f'{int(k):020d}')
    except (TypeError, ValueError):
        return (1, str(k))


# ---------------------------------------------------------------------------
#  Rendering
# ---------------------------------------------------------------------------

def render(result: dict[str, Any]) -> str:
    v = result['verdict']
    lines: list[str] = []
    if v == VERDICT_REORDERED:
        lines.append('VERDICT: REORDERED — the pane layout genuinely changed.')
    elif v == VERDICT_SET_CHANGED:
        lines.append('VERDICT: SET-CHANGED — NOT a reorder; a pane was opened or closed.')
    else:
        lines.append('VERDICT: NO-CHANGE — the layout is identical.')
    lines.append(f'  why: {result["reason"]}')
    lines.append(f'  panes before={result["before_count"]} after={result["after_count"]}')
    if result['gone']:
        lines.append(f'  gone: {", ".join(result["gone"])}')
    if result['new']:
        lines.append(f'  new:  {", ".join(result["new"])}')
    for m in result['moved']:
        lines.append(
            f'  moved: window {m["id"]}  '
            f'{_fmt_member(m["before"])}  ->  {_fmt_member(m["after"])}')
    lines.append(f'verdict={v}')
    return '\n'.join(lines)


def _fmt_member(m: dict[str, Any]) -> str:
    n = m.get('n') or {}
    parts = [f'{d}={n[d]}' for d in DIRECTIONS if d in n] or ['no-neighbours']
    return f'[osw {m.get("osw")} tab {m.get("tab")}] ' + ' '.join(parts)


# ---------------------------------------------------------------------------
#  CLI
# ---------------------------------------------------------------------------

def _load(path: str) -> Any:
    try:
        if path == '-':
            text = sys.stdin.read()
        else:
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
    except OSError as exc:
        raise GraphError(f'cannot read {path}: {exc}') from exc
    if not text.strip():
        raise GraphError(f'{path} is empty — an empty document is NOT an empty layout')
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise GraphError(f'{path} is not valid JSON: {exc}') from exc


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        prog='kitty-pane-graph.py',
        description='Pane-adjacency graph snapshot + witness-safe differ for W4.')
    sub = p.add_subparsers(dest='cmd', required=True)

    ps = sub.add_parser('snapshot', help='normalise a `kitten @ ls` dump')
    ps.add_argument('--ls', default='-', help='path to the ls JSON, or - for stdin')
    ps.add_argument('--out', default='-', help='where to write the snapshot, or - for stdout')

    pd = sub.add_parser('diff', help='compare two documents and print a verdict')
    pd.add_argument('before')
    pd.add_argument('after')
    pd.add_argument('--expect', choices=[VERDICT_NO_CHANGE, VERDICT_REORDERED,
                                         VERDICT_SET_CHANGED],
                    help='exit 1 unless the verdict is this word')
    pd.add_argument('--json', action='store_true', help='emit the verdict record as JSON')

    args = p.parse_args(argv)

    try:
        if args.cmd == 'snapshot':
            snap = coerce_snapshot(_load(args.ls))
            text = json.dumps(snap, indent=2, sort_keys=True)
            if args.out == '-':
                print(text)
            else:
                with open(args.out, 'w', encoding='utf-8') as fh:
                    fh.write(text + '\n')
                print(f'wrote {args.out} ({len(snap["members"])} pane(s))')
            return 0

        before = coerce_snapshot(_load(args.before))
        after = coerce_snapshot(_load(args.after))
        result = diff_graphs(before, after)
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
            print(f'verdict={result["verdict"]}')
        else:
            print(render(result))
        if args.expect and result['verdict'] != args.expect:
            print(f'EXPECTATION FAILED: wanted {args.expect}, got {result["verdict"]}',
                  file=sys.stderr)
            return 1
        return 0
    except GraphError as exc:
        # An instrument fault is a NON-VERDICT.  It must never be reported as
        # NO-CHANGE, and it must not exit 0.
        print(f'kitty-pane-graph: INSTRUMENT ERROR — {exc}', file=sys.stderr)
        print('verdict=ERROR', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
