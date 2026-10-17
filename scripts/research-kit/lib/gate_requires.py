"""gate_requires.py — may this build wave fire? (REPORT.md §3.10 "Carried rows at build time", §5.4;
§8 item 13; SYNTHESIS §6.3 "A build wave fires only when no row in its dependency closure is open or
carried-unresolved"). The reader behind `handoff-fire.sh --requires-gate <program>`.

  gate.sh requires --program P [--wave W] [--after-signoff] [--json]

A wave fires only when ALL of these hold:
  1. the registry reads `certified` (registered, certifying and closed all refuse: no build wave
     fires before the gate passes, and a reopen sets the registry back to registered);
  2. the newest certificate exists and carries no FAIL row;
  3. no VALID operator reopen is signed after that certificate (the registry may not have caught up:
     only `gate.sh run` moves it back, §5.1);
  4. nothing in the LIVE records blocks W:
       - a class-C decision still open or carried whose `blocks_waves` names W;
       - a carried set whose `blocks_waves` names W, unless W owns its narrowing probe
         (`set.narrowing_probe.wave`: "a carried set is exempt for the build wave that owns its
         narrowing probe");
       - any other open or carried decision whose `blocks_waves` names W;
       - an open frame-omission known row whose `blocks_waves` names W (§5.4);
       - W in any decision's or known row's `descoped_waves`: the sweep descoped it, so it does not
         build (a descoped wave is not a refused wave that will clear; it is a wave that is gone);
       - a premise filed not-yet-true (`cc-research premise file`) whose waves name W (the filing's
         `blocks_waves` plus its dependent decisions', less its owner wave), until its closing probe
         has run and joined the premise (the build-time re-check of decision 55e7da1e7311).

The records are read LIVE, not from the certificate's snapshot, because the things that clear a block
all happen after the certificate: the sweep converts a class-C row and closes an overdue known row by
appending events (gate_sweep.py), and a frame-delta cycle closes the known row it names. Reading the
snapshot would refuse forever a wave whose row has since closed, which is exactly §10 item 9's defect.
The gate rows themselves are NOT re-run here: a fire must not re-execute every probe, and row 10
(freshness) is the gate's job; the certificate is the gate's verdict and this verb reads it.

Method v1.2 (§11): in `implementation-signed` a wave fires only while a VALID operator signature
still pins the newest built certificate, and `--after-signoff` (handoff-fire `--gate-after-signoff`)
marks a wave that FOLLOWS implementation signoff: it is refused in every other state.

Without --wave there is no dependency closure to scope to, so ANY block for ANY wave refuses
(fail closed) and the refusal says to pass --wave.

Wave ids (RECORDS.md "Wave ids"). Every block above matches a wave by its exact string, so a row
that spells the wave another way blocks nothing for it: on 2026-10-16 `--wave D0` listed truememory-
2-0's open KR-06 and KR-07 while `--wave Day0`, the id its fire recipe passes, read CLEAR. So W is
resolved first against the program's ONE set of wave ids (vocabulary(): every id its frame and live
records name): an id outside it exits 2 before any side effect, naming the near-miss; and while two
ids in the set are one wave spelled twice (kit.wave_near_miss: `D0`/`Day0`, `rel`/`release`), or a
blocking row names text that is no wave id at all, the wave is refused until `gate.sh rekey-wave`
re-spells the rows. A row the sweep closed by class-B packets holds its waves while they are
pending, and the sweep descopes them when the default fires (gate_sweep step 3b).

  gate.sh waves --program P [--json]
      the set, with where each id is named, its twins and stray text; exit 1 while not canonical.
  gate.sh rekey-wave --program P --row KR-n|DR-n --from X --to Y --reason T
      re-spell X as Y in one known row's or decision's wave fields, by an appended event that keeps
      the earlier row and records {from, to, fields, at, by, reason}; under the program lease. Refused,
      writing nothing, unless Y is a spelling of X (kit.wave_respells; moving a block to another wave
      changes what the row gates), the row names X, Y is a wave id, and X has not started.

Exit 0 the wave may fire · 1 refused (each reason printed) · 2 the program cannot be read
(unregistered, bad slug) or W is not one of its wave ids: the caller refuses on both and says which.
"""

from __future__ import annotations

import difflib
import json
import re
from typing import Any, Dict, List, Optional, Tuple

import kit

BLOCKING_DECISION_STATES = ("open", "carried", "reopened")

# Which store's spelling a twin should converge on, best first: the operator-signed frame, a wave that
# has started (its dues count from that spelling), an operator- or packet-ruled decision, then rows.
AUTHORITY = {
    "frame": 0,
    "started": 1,
    "decision": 2,
    "known-row": 3,
    "premise": 4,
    "read": 4,
}
REKEYABLE = ("decision", "known-row")


def vocabulary(ctx: Any) -> Dict[str, Any]:
    """The program's one set of wave ids, read from its frame and LIVE records:
      frame.json build_waves; per folded decision blocks_waves, descoped_waves, restored_waves and
      set.narrowing_probe.wave; per folded known row blocks_waves, descoped_waves, applied_in_wave;
      per live not-yet-true filing blocks_waves, owner_wave; the live scheduled-read filing's
      blocks_waves; every wave started in waves.jsonl.
    -> {"ids": {wave: [(where, field, kind)]}, "twins": [[a, b]], "stray": [{where, field, value,
    blocking}]}. A stray value is no wave id at all (free text, a number); it is `blocking` when the
    field it sits in can refuse a wave now, since such a row may then block any wave."""
    import scheduled_read
    from gate_rows_a import known_rows

    hits: List[
        Tuple[str, str, str, Any, bool]
    ] = []  # where, field, kind, value, blocking

    def add(where: str, field: str, kind: str, vals: Any, blocking: bool) -> None:
        for v in vals if isinstance(vals, list) else [vals]:
            if v is not None and v != "":
                hits.append((where, field, kind, v, blocking))

    add("frame.json", "build_waves", "frame", ctx.frame.get("build_waves") or [], False)
    for did, d in kit.fold(ctx.jsonl("decisions.jsonl")).items():
        add(
            str(did),
            "blocks_waves",
            "decision",
            d.get("blocks_waves") or [],
            d.get("status") in BLOCKING_DECISION_STATES,
        )
        add(str(did), "descoped_waves", "decision", d.get("descoped_waves") or [], True)
        add(
            str(did), "restored_waves", "decision", d.get("restored_waves") or [], False
        )
        npb = (
            (d.get("set") or {}).get("narrowing_probe")
            if isinstance(d.get("set"), dict)
            else None
        )
        if isinstance(npb, dict):
            add(
                str(did), "set.narrowing_probe.wave", "decision", npb.get("wave"), False
            )
    for kr in known_rows(ctx):
        live = kr.get("status", "open") == "open" or (
            bool(kr.get("packets")) and not kr.get("packets_resolved")
        )
        add(
            str(kr["id"]),
            "blocks_waves",
            "known-row",
            kr.get("blocks_waves") or [],
            live,
        )
        add(
            str(kr["id"]),
            "descoped_waves",
            "known-row",
            kr.get("descoped_waves") or [],
            True,
        )
        add(
            str(kr["id"]),
            "applied_in_wave",
            "known-row",
            kr.get("applied_in_wave"),
            False,
        )
    for row in kit.not_yet_rows(ctx.jsonl("residual.jsonl")).values():
        add(
            str(row.get("id")),
            "blocks_waves",
            "premise",
            row.get("blocks_waves") or [],
            True,
        )
        add(str(row.get("id")), "owner_wave", "premise", row.get("owner_wave"), False)
    sr = scheduled_read.live_filing(ctx.records)
    if sr:
        passed = (sr.get("read") or {}).get("verdict") == "PASS"
        add(
            str(sr.get("id")),
            "blocks_waves",
            "read",
            sr.get("blocks_waves") or [],
            not passed,
        )
    for w in kit.wave_starts(ctx.records):
        add("waves.jsonl", "started", "started", w, False)

    ids: Dict[str, List[Tuple[str, str, str]]] = {}
    stray: List[Dict[str, Any]] = []
    for where, field, kind, v, blocking in hits:
        if isinstance(v, str) and kit.WAVE_ID_RE.match(v):
            if (where, field, kind) not in ids.setdefault(v, []):
                ids[v].append((where, field, kind))
        else:
            stray.append(
                {"where": where, "field": field, "value": v, "blocking": blocking}
            )
    names = sorted(ids)
    twins = [
        [a, b]
        for i, a in enumerate(names)
        for b in names[i + 1 :]
        if kit.wave_near_miss(a, b)
    ]
    return {"ids": ids, "twins": twins, "stray": stray}


def _rows(src: List[Tuple[str, str, str]]) -> List[str]:
    out: List[str] = []
    for where, _, _ in src:
        if where not in out:
            out.append(where)
    return out


def twin_reason(slug: str, v: Dict[str, Any], a: str, b: str) -> str:
    """Why neither spelling of one wave fires, and the re-key that converges them: the rows of the
    spelling the less authoritative stores use (AUTHORITY) move to the other's."""
    sa, sb = v["ids"][a], v["ids"][b]

    def rank(src: List[Tuple[str, str, str]]) -> int:
        return min(AUTHORITY.get(k, 9) for _, _, k in src)

    dst, src_w = (a, b) if rank(sa) <= rank(sb) else (b, a)
    movable = [w for w, _, k in v["ids"][src_w] if k in REKEYABLE]
    if not movable:  # the other direction, if that side is re-keyable
        dst, src_w = src_w, dst
        movable = [w for w, _, k in v["ids"][src_w] if k in REKEYABLE]
    head = (
        f"wave ids {a} and {b} spell one wave two ways ({a}: {', '.join(_rows(sa))}; {b}: "
        f"{', '.join(_rows(sb))}): a row keyed on one is not counted for the other, so neither "
        "fires until the records agree"
    )
    if not movable:
        return (
            f"{head}; no row on either side is one rekey-wave re-spells (a decision or known row): "
            "correct the frame's build_waves by a re-signed frame, or refile the row"
        )
    rows = sorted(set(movable), key=movable.index)
    return (
        f"{head}; re-key {', '.join(rows)}: `gate.sh rekey-wave --program {slug} --row {rows[0]} "
        f"--from {src_w} --to {dst} --reason …`"
        + (" (once per row)" if len(rows) > 1 else "")
        + ", or the reverse"
    )


def stray_reason(slug: str, s: Dict[str, Any]) -> str:
    return (
        f"{s['where']} {s['field']} names {s['value']!r}, which is not a wave id: it may block any "
        f"wave, so every wave waits until it is re-keyed (`gate.sh rekey-wave --program {slug} --row "
        f"{s['where']} --from {str(s['value'])!r} --to <wave> --reason …`)"
    )


def resolve_wave(slug: str, wave: str) -> None:
    """Raise KitError (exit 2, before any side effect) unless `wave` is one of the program's ids."""
    import gate

    if kit.registry_get(slug) is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    ids = vocabulary(gate.make_ctx(slug))["ids"]
    if wave in ids:
        return
    near = sorted(w for w in ids if kit.wave_near_miss(wave, w))
    close = [
        w
        for w in difflib.get_close_matches(wave, list(ids), n=3, cutoff=0.6)
        if w not in near
    ]
    raise kit.KitError(
        f"unknown wave id {wave!r} for {slug}"
        + (f"; near-miss: {', '.join(near)}" if near else "")
        + (f"; did you mean {', '.join(close)}?" if close and not near else "")
        + f"; its wave ids: {', '.join(sorted(ids)) or 'none'} (gate.sh waves --program {slug}). "
        "A wave no record names cannot be gated: the frame's build_waves or the row that gates it "
        "must name it"
    )


def _names(wave: Optional[str], waves: Any) -> bool:
    ws = [w for w in (waves or []) if isinstance(w, str) and w]
    return bool(ws) if wave is None else wave in ws


def _cert_no(p: Any) -> int:
    m = re.match(r"CERT-v(\d+)\.json$", p.name)
    return int(m.group(1)) if m else -1


def blockers(
    slug: str, wave: Optional[str], after_signoff: bool = False
) -> Dict[str, Any]:
    """{"cert": id|None, "reasons": [str]} — empty reasons means the wave may fire."""
    import gate
    from gate_rows_a import known_rows

    reasons: List[str] = []
    prog = kit.registry_get(slug)
    if prog is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    state = prog.get("state")
    # a fix wave runs during Stage 9 (REPORT.md §11), so both build states fire a wave too
    if state not in ("certified",) + kit.STAGE9_STATES:
        reasons.append(
            f"registry state is {state!r}, not 'certified': no build wave fires before the gate passes"
        )
    if state == kit.IMPL_SIGNED or after_signoff:
        import gate_built

        ok, why = gate_built.implementation_gate(slug)
        if state == kit.IMPL_SIGNED and not ok:
            reasons.append(f"registry state is 'implementation-signed' but {why}")
        elif after_signoff and state != kit.IMPL_SIGNED:
            reasons.append(
                f"this wave follows implementation signoff and the registry state is {state!r}: {why}"
                if not ok
                else f"this wave follows implementation signoff and the registry state is {state!r}: "
                f"run gate.sh built-signed --program {slug}"
            )
    ctx = gate.make_ctx(slug)
    certs = sorted(ctx.records.glob("cert/CERT-v*.json"), key=_cert_no)
    cert: Dict[str, Any] = {}
    if not certs:
        reasons.append(f"no certificate under {ctx.records / 'cert'}")
    else:
        cert = kit.read_json(certs[-1], {}) or {}
        failed = sorted(
            (k for k, v in (cert.get("rows") or {}).items() if v == gate.FAIL), key=int
        )
        if failed:
            reasons.append(f"{cert.get('cert')}: FAIL row(s) {', '.join(failed)}")
        if not cert.get("rows"):
            reasons.append(f"{certs[-1].name} carries no rows — unknown fails (§3.10)")
        # Method v1.3 (REPORT.md §13): the certificate carries FILED rows (a scheduled read, keyed
        # dues), so no wave builds on it until the operator has accepted it by signing THIS
        # certificate; an agent-written or stale signature, or one on an earlier version, is none.
        # §14: an acceptance under the operator's standing delegation counts exactly as his signature.
        import operator_sign

        sig = operator_sign.latest_valid(slug, "cert")
        if not sig or f"cert/{certs[-1].name}" not in (sig.get("pins") or {}):
            reasons.append(
                f"{certs[-1].stem} is not signed by the operator (cc-signoff research:{slug}/cert) "
                f"nor accepted by delegation (gate.sh accept --program {slug} --action cert)"
            )
    if gate.reopened(ctx):
        reasons.append(f"{gate.reopen_phrase(ctx)} after the newest certificate")

    voc = vocabulary(ctx)
    for a, b in voc["twins"]:
        if wave is None or wave in (a, b):
            reasons.append(twin_reason(slug, voc, a, b))
    reasons += [stray_reason(slug, s) for s in voc["stray"] if s["blocking"]]

    for d in kit.fold(ctx.jsonl("decisions.jsonl")).values():
        did = d.get("id")
        if wave is not None and wave in (d.get("descoped_waves") or []):
            reasons.append(
                f"{did}: descoped wave {wave} (the sweep converted it; it does not build)"
            )
            continue
        st = d.get("status")
        if st not in BLOCKING_DECISION_STATES or not _names(
            wave, d.get("blocks_waves")
        ):
            continue
        pk = d.get("packet") or {}
        npb = (d.get("set") or {}).get("narrowing_probe") or {}
        if pk.get("class") == "C":
            reasons.append(
                f"{did}: unresolved class-C row (due {pk.get('due') or '?'}) blocks "
                f"{', '.join(d.get('blocks_waves') or [])}"
            )
        elif st == "carried" and d.get("set"):
            if wave is not None and npb.get("wave") == wave:
                continue  # this wave owns the set's narrowing probe
            reasons.append(
                f"{did}: carried set (narrows in {npb.get('wave') or '?'}) blocks "
                f"{', '.join(d.get('blocks_waves') or [])}"
            )
        else:
            reasons.append(
                f"{did}: {st} decision blocks {', '.join(d.get('blocks_waves') or [])}"
            )

    for kr in known_rows(ctx):
        kid = kr.get("id")
        if wave is not None and wave in (kr.get("descoped_waves") or []):
            reasons.append(
                f"{kid}: descoped wave {wave} (closed by its default; it does not build)"
            )
            continue
        pids = [str(p) for p in kr.get("packets") or []]
        if (
            pids
            and not kr.get("packets_resolved")
            and _names(wave, kr.get("blocks_waves"))
        ):
            ws = list(kr.get("blocks_waves") or [])
            reasons.append(
                f"{kid}: closed by its default; class-B packet {', '.join(pids)} (default descope) is "
                f"pending, so {', '.join(ws)} {'waits' if len(ws) == 1 else 'wait'} until it fires "
                f"(descoped) or the operator vetoes it (cc-signoff research:{slug}/veto/{kid})"
            )
            continue
        if kr.get("status", "open") != "open" or not _names(
            wave, kr.get("blocks_waves")
        ):
            continue
        reasons.append(
            f"{kid}: open {kr.get('kind') or 'known'} row (rows {', '.join(kr.get('names_rows') or []) or '-'}) "
            f"blocks {', '.join(kr.get('blocks_waves') or [])} until its frame-delta cycle closes it"
        )

    # A premise filed not-yet-true (decision 55e7da1e7311) is a bet the certificate placed on the
    # build. The build-time re-check: every wave resting on it waits until its closing probe has run
    # and joined the premise; the owner wave, which runs that probe, is never refused by it. If the
    # probe refuted the premise, the waves also wait for its dependents to be revised (gate row 4).
    from gate_rows_a import refuted_at, unrevised_dependents

    prem_events = ctx.jsonl("premises.jsonl")
    prem = kit.fold(prem_events)
    dec_events = ctx.jsonl("decisions.jsonl")
    decs = kit.fold(dec_events)
    probes = kit.fold(ctx.jsonl("probes.jsonl"))
    for pid, row in sorted(kit.not_yet_rows(ctx.jsonl("residual.jsonl")).items()):
        p = prem.get(pid) or {"id": pid}
        ws = kit.not_yet_waves(row, p, decs)
        if not _names(wave, ws):
            continue
        cp = row.get("closing_probe") or "?"
        if not kit.not_yet_closed(row, p, probes):
            reasons.append(
                f"{pid}: filed not-yet-true until {row.get('owner_wave') or '?'} "
                f"({row.get('awaits') or '?'}); its closing probe {cp} has not run and joined it, "
                f"so {', '.join(ws)} wait (run {cp} with --closes {pid}, then "
                f"`cc-research premise revise --id {pid} --probe {cp}`)"
            )
        elif p.get("verdict") == "refuted":
            todo = unrevised_dependents(p, dec_events, refuted_at(prem_events))
            if todo:
                reasons.append(
                    f"{pid}: its closing probe {cp} joined and the premise is refuted; revise "
                    f"{', '.join(todo)} before {', '.join(ws)} fire"
                )

    # Method v1.3 (REPORT.md §13.1): row 15 filed as a scheduled read holds only the waves its
    # filing names, until the read passes; a FAIL keeps them held.
    import scheduled_read

    reasons += scheduled_read.blocks(ctx.records, wave)

    if wave is None and reasons:
        reasons.append(
            "no --wave given, so every block counts: pass the wave id to scope to its closure"
        )
    return {"cert": cert.get("cert"), "reasons": reasons}


def record_start(slug: str, wave: str, cert: Optional[str]) -> str:
    """Method v1.3 (REPORT.md §13.2): the first admitted `--start` of a wave appends one `started` row
    to waves.jsonl, the event a due keyed `<wave>+<N>d` resolves from. A later one records nothing."""
    import gate

    rec = gate.make_ctx(slug).records
    at = kit.wave_starts(rec).get(wave)
    if at:
        return f"wave {wave} already started at {at}"
    now = kit.now_iso()
    kit.append_jsonl(
        rec / kit.WAVES_LOG, {"wave": wave, "event": "started", "at": now, "cert": cert}
    )
    return f"STARTED {slug} wave {wave} at {now}"


def cmd_requires(a: Any) -> int:
    kit.check_slug(a.program)
    if a.wave is not None and not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", a.wave):
        raise kit.KitError(f"bad wave id {a.wave!r}")
    if a.start and a.wave is None:
        raise kit.KitError(
            "--start needs --wave: a start is recorded for one admitted wave"
        )
    if a.wave is not None:
        resolve_wave(a.program, a.wave)
    r = blockers(a.program, a.wave, a.after_signoff)
    ok = not r["reasons"]
    if ok and a.start:
        started = record_start(a.program, a.wave, r["cert"])
        if a.json:
            r = dict(r, started=started)
        else:
            print(started)
    if a.json:
        print(
            json.dumps(
                dict(
                    r,
                    program=a.program,
                    wave=a.wave,
                    verdict="clear" if ok else "refused",
                )
            )
        )
    else:
        where = f"wave {a.wave}" if a.wave else "every wave"
        if ok:
            print(
                f"CLEAR {a.program} {where}: {r['cert']} carries nothing that blocks it"
            )
        else:
            print(f"REFUSED {a.program} {where}:")
            for x in r["reasons"]:
                print(f"  - {x}")
    return 0 if ok else 1


def cmd_waves(a: Any) -> int:
    import gate

    slug = kit.check_slug(a.program)
    if kit.registry_get(slug) is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    v = vocabulary(gate.make_ctx(slug))
    ok = not v["twins"] and not any(s["blocking"] for s in v["stray"])
    labels = {
        w: [f"{where} {field}" for where, field, _ in src]
        for w, src in v["ids"].items()
    }
    if a.json:
        print(
            json.dumps(
                {
                    "program": slug,
                    "canonical": ok,
                    "ids": labels,
                    "twins": v["twins"],
                    "stray": v["stray"],
                },
                sort_keys=True,
            )
        )
        return 0 if ok else 1
    print(f"{slug}: {len(labels)} wave id(s){'' if ok else ', NOT canonical'}")
    for w in sorted(labels):
        print(f"  {w}: {', '.join(labels[w])}")
    for x, y in v["twins"]:
        print(f"TWINS {x} / {y}: {twin_reason(slug, v, x, y)}")
    for s in v["stray"]:
        print(
            f"STRAY {s['where']} {s['field']}: {s['value']!r} "
            + (
                "(it blocks now: every wave waits)"
                if s["blocking"]
                else "(blocks nothing now)"
            )
        )
    return 0 if ok else 1


def cmd_rekey(a: Any) -> int:
    import gate
    from gate_rows_a import known_rows

    slug = kit.check_slug(a.program)
    if kit.registry_get(slug) is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    src, dst = a.src, a.dst
    if not kit.WAVE_ID_RE.match(dst):
        raise kit.KitError(f"bad wave id {dst!r} for --to")
    if src == dst:
        raise kit.KitError(f"--from and --to are both {src!r}: nothing to re-key")
    ctx = gate.make_ctx(slug)
    krs = {str(r["id"]): r for r in known_rows(ctx)}
    decs = kit.fold(ctx.jsonl("decisions.jsonl"))
    if a.row in krs and a.row in decs:
        raise kit.KitError(
            f"{a.row} is both a known row and a decision; re-key refused"
        )
    if a.row in krs:
        store, rec = "known_rows.jsonl", krs[a.row]
        fields = ("blocks_waves", "descoped_waves", "applied_in_wave")
    elif a.row in decs:
        store, rec = "decisions.jsonl", decs[a.row]
        fields = ("blocks_waves", "descoped_waves", "restored_waves", "set")
    else:
        raise kit.KitError(f"no known row or decision {a.row} in {slug}'s records")
    ev: Dict[str, Any] = {"id": a.row}
    changed: List[str] = []
    for f in fields:
        val = rec.get(f)
        if f == "set":
            npb = val.get("narrowing_probe") if isinstance(val, dict) else None
            if isinstance(npb, dict) and npb.get("wave") == src:
                new = json.loads(json.dumps(val))
                new["narrowing_probe"]["wave"] = dst
                ev["set"] = new
                changed.append("set.narrowing_probe.wave")
        elif isinstance(val, list) and src in val:
            out: List[Any] = []
            for w in val:
                w2 = dst if w == src else w
                if w2 not in out:
                    out.append(w2)
            ev[f] = out
            changed.append(f)
        elif val == src:
            ev[f] = dst
            changed.append(f)
    if not changed:
        raise kit.KitError(f"{a.row} names no wave {src}")
    if not kit.wave_respells(src, dst):
        raise kit.KitError(
            f"{dst} is not a spelling of {src}: a re-key moves a row to the same wave spelled another "
            "way, never to another wave, which would change what the row gates"
        )
    started = kit.wave_starts(ctx.records)
    if src in started:
        raise kit.KitError(
            f"wave {src} started at {started[src]}: its keyed dues count from that start, so the "
            "spelling it started under stays"
        )
    ev["rekeyed"] = {
        "from": src,
        "to": dst,
        "fields": changed,
        "at": kit.now_iso(),
        "by": kit.lease_owner(),
        "reason": a.reason,
    }
    kit.append_jsonl(ctx.records / store, ev)
    print(
        f"REKEYED {a.row}: {src} -> {dst} in {', '.join(changed)} (an event appended to {store}; "
        "the earlier row is kept)"
    )
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("waves")
    p.add_argument("--program", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_waves)
    p = sub.add_parser("rekey-wave")
    p.add_argument("--program", required=True)
    p.add_argument(
        "--row", required=True, help="the known row (KR-n) or decision (DR-n) to re-key"
    )
    p.add_argument("--from", dest="src", required=True)
    p.add_argument("--to", dest="dst", required=True)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_rekey)
    p = sub.add_parser("requires")
    p.add_argument("--program", required=True)
    p.add_argument("--wave")
    p.add_argument("--after-signoff", action="store_true")
    p.add_argument(
        "--start",
        action="store_true",
        help="record the wave's start when it is admitted (method v1.3: keyed dues count from it)",
    )
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_requires)
