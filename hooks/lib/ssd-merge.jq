# ssd-merge.jq — the merge program of hooks/session-start-dispatch.sh (dispatcher v2).
# Spec: docs/research/startup-hooks-2026-10-18/A3-dispatcher.md §4.2-4.5, README rows #2 #14 #19.
#
# WHY A FILE. The merge used to be inline in the shell, untestable on its own and with nowhere to
# keep the child table as data. It stays jq on purpose: JSON-escaping the 2 KB ANSI board in bash 3.2
# costs 37 ms at 2 KB and 2.1 s at 8 KB, against ~10 ms for this whole program (A3 skeptic R9).
#
# INPUTS (`jq -nc -f ssd-merge.jq …`):
#   --rawfile status  one line per registered child, in registration order:
#                     NN<TAB>name<TAB>done|late|absent|killed<TAB>rc-or-dash
#   --rawfile times   `stat -f '%Fm %N'` of t0 and every rNN: ns mtimes, one fork times every child
#   --rawfile oNN     stdout of child NN. Merged only when the child is `done` with rc < 129; a
#                     killed child's partial output is measured (its size is named) and never merged.
#   --arg mode main|late · sid src cfg ledger home dir
#   --argjson cap smcap emit late lag pid ppid
# OUTPUT: line 1 = the hook JSON to print, or null (print nothing); then the ledger row(s), one per
# run in main mode, one per late child in late mode. -c keeps each on one line, so the shell splits
# them off with parameter expansion and no fork.
#
# A HEALTHY RUN PRINTS V1'S BYTES. Every child done, nothing named, both channels under their caps:
# line 1 is what v1 printed — registration order, "\n" joins, the same keys in the same order.

def tilde: if startswith($home + "/") then "~" + .[($home | length):] else . end;

# The child table (A3 §4.3). tier orders the context cut, and tier 0 (the recycle packet) is never
# cut. model is the line the MODEL gets when that child's context is missing (banner children cost
# 0 tokens on a drop). fix is the operator's recovery command, taken from each child's own header.
def table: {
  "recycle-failed-inject.sh": {tier: 0, what: "the failed-recycle check",
    model: "RECYCLE CHECK INCOMPLETE — if ~/.claude/autonomy/recycle-failed/\($sid).prompt.md exists, read it and act on it first.",
    fix: "ls ~/.claude/autonomy/recycle-failed/\($sid).*",
    pkt: "~/.claude/autonomy/recycle-failed/\($sid).prompt.md"},
  "session-start.sh": {tier: 1, what: "the MCP status line",
    model: "MCP status line missing this start; do not assume MCP servers are connected.",
    fix: "tail ~/.claude/logs/sessions.log"},
  "setup-plan-symlinks.sh": {tier: 2, what: "the Plans line",
    model: "Plans line missing this start; run find-plan.sh --list-open for the open plans.",
    fix: "find-plan.sh --list-open"},
  "setup-task-symlinks.sh": {tier: 2, what: "the Tasks line",
    model: "Tasks line missing this start; active tasks are under .claude-tasks/_current/.",
    fix: "ls .claude-tasks/_current/"},
  "session-index-start.sh": {tier: 3, what: "the session-index row", model: null, fix: null},
  "frontier-status.sh": {tier: 3, what: "the Frontier line", model: null, fix: null},
  "lever-arm-start.sh": {tier: 3, what: "the usage-lever session stamp", model: null,
    fix: "tail -1 ~/.claude/logs/lever-arms.jsonl"},
  "accounts-board.sh": {tier: 3, what: "the accounts board", model: null, fix: "claude-accounts"},
  "activation-watch.sh": {tier: 3, what: "the activation notices", model: null,
    fix: "bash ~/.claude/hooks/activation-watch.sh --queue"},
  "escalation-watch.sh": {tier: 3, what: "the escalation notices", model: null,
    fix: "tail ~/.claude/logs/autonomy-sweep*.log"},
  "config-mirror-assert.sh": {tier: 3, what: "the mirror/parity/drift/budget checks", model: null,
    fix: "zsh -fc 'source ~/.claude/lib/config-mirror.zsh; _cc_sync_account ~/\($cfg)'"}
};
def info($c): (table | .[$c]) // {tier: 3, what: "its output", model: null, fix: null};

def lines($s): $s | split("\n") | map(select(length > 0));
def mtimes: [ lines($times)[] | capture("^(?<t>[0-9]+(\\.[0-9]+)?) (?<p>.+)$")
              | {key: (.p | sub("^.*/"; "")), value: (.t | tonumber)} ] | from_entries;
def str: if type == "string" then . elif . == null then "" else null end;
def nothing: {ctx: "", sm: "", wp: [], title: null, reload: false, bad: null, drop: []};

# A done child's raw stdout → its contribution. v1's contract: a JSON object gives its two
# channels; any other stdout is plain context, which is how the harness reads a plain-text hook.
def parse:
  rtrimstr("\n") as $v
  | (try ($v | fromjson | {ok: true, j: .}) catch {ok: false}) as $p
  | if $v == "" then nothing
    elif $p.ok and ($p.j | type) == "object" then
      $p.j as $j | ($j.hookSpecificOutput // {}) as $h | (($h | type) == "object") as $ho
      | (if $ho then ($h.additionalContext | str) else "" end) as $ac
      | ($j.systemMessage | str) as $sm
      | (if $ho then $h.watchPaths else null end) as $w
      | {ctx: ($ac // ""), sm: ($sm // ""),
         wp: (if ($w | type) == "array" then [ $w[] | select(type == "string") ] else [] end),
         title: (if $ho and ($h.sessionTitle | type) == "string" then $h.sessionTitle else null end),
         reload: ($ho and $h.reloadSkills == true),
         bad: (if ($ho | not) or $ac == null or $sm == null or ($w != null and ($w | type) != "array")
               then "fields" else null end),
         # -p only (hooks.md SessionStart decision control): dropped, and the ledger says so
         drop: (if $ho and $h.initialUserMessage != null then ["initialUserMessage"] else [] end)}
    else
      # A `{` that does not parse is still merged as plain text (what the harness did), but named:
      # the child meant JSON there.
      nothing + {ctx: $v, bad: (if ($p.ok | not) and ($v | test("^\\s*\\{")) then "unparseable" else null end)}
    end;

def recs($t):
  [ lines($status)[] | split("\t")
    | {n: .[0], name: .[1], s: .[2], rc: (.[3] | tonumber? // null)} as $r
    | ($ARGS.named["o" + $r.n] // "") as $raw
    | (if $t.t0 != null and $t["r" + $r.n] != null
       then (($t["r" + $r.n] - $t.t0) * 1000 + 0.5 | if . < 0 then 0 else floor end) else null end) as $ms
    | (if $r.s == "done" and ($r.rc // 0) < 129 then ($raw | parse) else nothing end) as $o
    | $r + $o + {i: info($r.name), ms: $ms, pc: ($raw | length),
        st: (if $r.s == "absent" then "absent"
             elif $r.s == "late" then "late"
             elif $r.s == "killed" or ($r.rc // 0) >= 129 then "killed"
             elif $mode == "late" then (if ($r.rc // 0) == 0 then "late-ok" else "late-fail" end)
             elif $o.bad != null then "malformed"
             elif ($r.rc // 0) == 0 then "ok" else "fail" end)} ];

def merged: IN("ok", "fail", "malformed", "late-ok", "late-fail");
def fixs: if .i.fix then " · re-check: \(.i.fix)" else "" end;

# Context: whole-or-nothing per child, in tier order, so a child is either all there or named as
# gone (half a Plans line reads as a complete statement). Tier 0 alone over the budget is truncated
# with a pointer to its packet file, so nothing is lost. Model lines for missing model-facing
# children go first and come out of the budget.
def ctxplan($R):
  [ $R[] | select(.st | IN("late", "killed", "absent")) | .i.model // empty ] as $ml
  | ($cap - (if $ml == [] then 0 else ($ml | join("\n") | length) + 1 end)) as $B
  | [ $R | to_entries[] | select((.value.st | merged) and .value.ctx != "")
      | {k: .key, name: .value.name, tier: .value.i.tier, txt: .value.ctx,
         model: .value.i.model, pkt: .value.i.pkt, i: .value.i} ] as $cs
  | reduce ($cs | sort_by(.tier, .k))[] as $x ({rem: $B, n: 0, keep: {}, cut: [], trunc: []};
      (if .n > 0 then 1 else 0 end) as $sep
      | if ($x.txt | length) + $sep <= .rem then
          .rem -= ($x.txt | length) + $sep | .n += 1 | .keep[$x.k | tostring] = $x.txt
        elif $x.tier == 0 then
          ($x.txt | length) as $L
          | ("…[truncated \($L) chars — read the full packet: \($x.pkt // "its packet file")]" | length) as $pl
          | ([.rem - $sep - $pl, 0] | max) as $kept
          | "…[truncated \($L - $kept) chars — read the full packet: \($x.pkt // "its packet file")]" as $ptr
          | .keep[$x.k | tostring] = ($x.txt[:$kept] + $ptr)
          | .rem -= $kept + ($ptr | length) + $sep | .n += 1
          | .trunc += [$x + {dropped: ($L - $kept)}]
        else .cut += [$x] end)
  | . as $p
  | [ $cs[] | $p.keep[.k | tostring] // empty ] as $kept
  | [ $p.cut[] | .model // empty ] as $cml
  | (($ml + $cml + $kept) | join("\n")) as $full
  | {ctx: (if $cml != [] and ($full | length) <= $cap then $full else (($ml + $kept) | join("\n")) end),
     cut: $p.cut, trunc: $p.trunc};

# systemMessage: the notices first and never dropped, then the banners in registration order,
# dropped whole from the END until the message fits under the cap, each drop named.
def smplan($N; $bs):
  def body($kept; $drop):
    ($N + [ $drop[] | "⚠ startup: banners over the \($smcap)-char cap → dropped \(.name)'s banner (\(.txt | length) chars)\(fixs)" ]
        + [ $kept[].txt ]) | join("\n");
  {kept: $bs, drop: []}
  | until((body(.kept; .drop) | length) <= $smcap or .kept == [];
          .drop = [.kept[-1]] + .drop | .kept = .kept[:-1])
  | {sm: body(.kept; .drop), dropped: .drop};

def notice:
  if .st == "late" then
    "⚠ startup: \(.name) still running at \($emit)s → \(.i.what) NOT shown this start; its result logs to \($ledger | tilde) (late row)\(fixs)"
  elif .st == "killed" then
    "⚠ startup: \(.name) was killed \(if $mode == "late" then "at the \($late)s backstop" else "(rc \(.rc))" end) → its partial output\(if .pc > 0 then " (\(.pc) chars)" else "" end) was dropped, not merged\(fixs)"
  elif .st == "absent" then
    "⚠ startup: \(.name) is missing or not executable in \($dir | tilde) → \(.i.what) skipped this start · re-install: bash ~/Development/claude-infrastructure/install.sh"
  elif .st == "malformed" then
    "⚠ startup: \(.name) printed \(if .bad == "unparseable" then "unparseable JSON (\(.ctx | length) chars) → merged as plain context, as the harness would" else "hook JSON with a wrong-typed field → that field was dropped" end)\(fixs)"
  else empty end;

mtimes as $T
| recs($T) as $R
| ctxplan($R) as $C
| ([ $R[] | notice ]
   + [ $C.cut[] | "⚠ startup: context over the \($cap)-char cap → dropped \(.name)'s context (\(.txt | length) chars)\(fixs)" ]
   + [ $C.trunc[] | "⚠ startup: context over the \($cap)-char cap → \(.name) truncated (\(.dropped) chars dropped; the full packet is on disk)" ]) as $N
| [ $R[] | select((.st | merged) and .sm != "") | {name, txt: .sm, i} ] as $bs
| smplan($N; $bs) as $S
# Extra SessionStart fields (A6 D8, gap-G2 G2-4): watchPaths as an order-kept union, the first
# sessionTitle in registration order, reloadSkills if any child asks. A late child's cannot apply.
| (if $mode == "main" then [ $R[] | select(.st | merged) ] else [] end) as $M
| (reduce ($M[] | .wp[]) as $w ([]; if any(.[]; . == $w) then . else . + [$w] end)) as $wp
| ([ $M[] | .title // empty ] | .[0]) as $title
| any($M[]; .reload) as $reload
| ((if $C.ctx != "" or $wp != [] or $title != null or $reload then
      {hookSpecificOutput: ({hookEventName: "SessionStart"}
         + (if $C.ctx != "" then {additionalContext: $C.ctx} else {} end)
         + (if $wp != [] then {watchPaths: $wp} else {} end)
         + (if $title != null then {sessionTitle: $title} else {} end)
         + (if $reload then {reloadSkills: true} else {} end))}
    else {} end)
   + (if $S.sm != "" then {systemMessage: $S.sm} else {} end)
   | if length > 0 then . else null end) as $out
| [ $C.cut[].name ] as $cc | [ $S.dropped[].name ] as $sd | [ $C.trunc[].name ] as $tr
| def kid:
    {c: .name, st: (if (.name | IN($cc[], $sd[])) then "cut" else .st end), rc, ms,
     cc: (if .st | merged then (.ctx | length) else null end),
     sc: (if .st | merged then (.sm | length) else null end)}
    + (if .name | IN($cc[]) then {cut: "ctx"} elif .name | IN($sd[]) then {cut: "sm"}
       elif .name | IN($tr[]) then {cut: "trunc"} else {} end)
    + (if .st == "killed" then {pc} else {} end)
    + (if .drop != [] then {dropped_fields: .drop} else {} end);
  $out,
  (if $mode == "late" then
     $R[] | {v: 1, kind: "late", ts: (now | floor | todate), sid: $sid, src: $src, cfg: $cfg, pid: $pid} + kid
   else
     {v: 1, ts: (now | floor | todate), sid: $sid, src: $src, cfg: $cfg, pid: $pid, ppid: $ppid,
      lag_s: $lag, emit_s: $emit,
      total_ms: (if $T.t0 != null then ((now - $T.t0) * 1000 | floor) else null end),
      printed: ($out != null), ctx_out: ($C.ctx | length), sm_out: ($S.sm | length),
      kids: [ $R[] | kid ],
      notices: ([ $R[] | select(.st | IN("late", "killed", "absent", "malformed")) | "\(.name) \(.st)" ]
                + [ $cc[], $sd[] | "\(.) cut" ] + [ $tr[] | "\(.) truncated" ])}
   end)
