# curl-gate: unresolved $ in a URL authority — resolve-then-close

Read-only. Trunk = origin/main @95d54abd5 (curl-gate.py @767615fac; live copy == trunk).
Commands evaluated only as strings through decide_command(); no curl, no network, no edits.
Scratch: /tmp/hookdec5/curl_gate_{trunk,blanket,rtc,rtc2}.py

## Finding, sized
Trunk treats an unresolved $ in a URL authority as a literal host and allows it.
replay.json (8,058 tool_use_ids, 45d): 57 allows carry $ in netloc; 41 in the HOST label
(= the brief's set, 41/41); the other 16 have $ only in the PORT (localhost:$PORT) — no SSRF
reach, correctly excluded.

## Q1 — why the 41 are unresolved
Trunk ALREADY resolves literal loop/assign values in host position: `for h in studio60
insomniacdenver; curl $h.reso.gl` and `A=studio60; curl $A.reso.gl` resolve today, and
`H=169.254.169.254; curl $H` already DENIES. The 41 are genuinely runtime, not a host blind spot:
- ~18 command-substitution assigns X=$(...) (shell_bindings marks $(/backtick bad)
- ~9  while read / read -r / read <<< (an _UNSEEN_BINDER)
- ~5  for-list is itself $(...) (loop_words_literal False)
- ~7  positional $1 inside a shell function probe(){ "$1" }
- ~2  source/let/. before the loop
- 1   ONLY genuine resolver gap: identical for-loop bound twice; shell_bindings keeps names bound
      exactly once, so `for h in studio60 insomniacdenver` twice drops h even though both lists match.
Confirmed host-position bypasses trunk allows (checked vs /bin/zsh -f, as strings):
read H <<< 169.254.169.254; curl http://$H/ ; curl "http://$(echo 169.254.169.254)/" ; printf -v,
${h::=}, foreach, short-for, zstyle -s, anon-func, `H=x curl $H`.

## Q2 — resolve-then-close prototype + replay
rtc2 (recommended): (1) shell_bindings also binds a name whose repeated sites are all identical;
(2) ask only when $/backtick remains in u.hostname after expansion (port-only $ stays allow).
Every flip across all corpora is allow->ask; ZERO allow->deny, ZERO loosening:
  replay.json 45d: 40  (= 41 minus the 1 double-loop rtc2 now resolves to allow)
  tx_curl.jsonl 37d: 77 (wider/undeduped; same shapes)
  ~/.reso/curl-audit.jsonl: 43 (redacted)
New allows vs trunk: 0 (resolve step only PREVENTS the 1 double-loop flip).
Decoys: 5 brief-named + 10 crafted, all host-position -> all ask-or-deny under rtc2, 0 leak
(trunk allowed 11/15). h="169.254.169.254/#".reso.gl and H2=$H chain -> deny.
Out-of-scope residuals unchanged by rtc2 (different class, not authority-$): `alias curl=... #`
and `set -- "http://169.254..."; for u; do curl "$u"` still allow on both.
blanket variant (ask on any $ in netloc) flips 57 — 17 worse: it also stalls the 16 localhost
:$PORT rows and the double-loop reso probe. rtc2 strictly dominates.

## Q3 — subagent vs main split (transcript file under <sid>/subagents/**, x-checked isSidechain)
  tx_curl flips (77):        subagent 68 (88%) | main 9 (12%)
  replay canonical (38/40):  subagent 32 (84%) | main 6 (16%)
Subagent flips are the parallel-probe patterns: reso tenant sweeps, flickr/bottle asset loops,
sevenrooms route probes, probe(){ "$1" } image loops.

## Recommendation
Resolve-then-close, host-scoped (rtc2). Closes every host-position SSRF decoy with 0 leaks and 0
loosening across 3 corpora; strictly better than blanket (spares 17 legit flips). The resolve
change is safe: differing repeated bindings still refuse.

## Strongest counter
85-88% of flips land in SUBAGENTS, where an interactive ask cannot be answered — it stalls/denies
legitimate runtime-host reso probes, reproducing the 126-ask/~50h stall that drove the earlier
loopback relaxation. Mitigant: resolvable literal-loop reso probes stay allow under rtc2; only
genuinely runtime hosts (read/$(...)/$1) flip — statically indistinguishable from SSRF, so ask is
the correct posture. Residual if left open: the confirmed read<<< / $(echo) host bypasses stay live.
