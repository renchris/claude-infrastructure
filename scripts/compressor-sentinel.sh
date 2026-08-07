#!/bin/bash
# compressor-sentinel.sh — the one sensor that cannot be starved, for the thing that keeps killing
# this box: VM-compressor SEGMENT exhaustion (three kernel panics in six days, 2026-07-30 → 08-05).
#
# WHY A NEW DAEMON RATHER THAN ANOTHER RUNG ON capacity-alarm.sh
# (docs/research/panic-compressor-2026-08-05.md §5 — the sensor postmortem):
#   · EVERY existing rung read a HEALTHY box at death. 20 GB free, swap idle, pressure normal, and
#     the kernel's own memorystatus verdict already `"compressor_exhausted": 1`. Headroom, swap and
#     pressure are not slow versions of this signal — they are blind to it.
#   · The one instrument that CAN see the descriptor count, `zprint`, HANGS under the very storm it
#     measures (the 00:14 run was still TH_WAIT at panic). So it is banned from the tick here.
#     §7.7's cheap-sysctl recipe replaces it: in-core segments ≈ vm_stat "Pages occupied by
#     compressor" ÷ (segment_buffer / pagesize), swapped segments = vm.swapusage used ÷ 65536
#     (EXACT — swap is allocated in 64 KiB compressed chunks). Their sum tracks c_segment_count.
#   · capacity-alarm.sh runs at ProcessType Adaptive on a 60 s StartInterval. That is right for a
#     capacity report and wrong for this: §6 discriminator 4 records that the background-band
#     sampler's own DEATH — the absence of its row — was the earliest machine-readable distress
#     signal in all three events, firing ~3 min before the wedge. A sampler that dies during the
#     event cannot be the guard for the event. Hence: internal loop, no launchd band, no ProcessType.
#
# WHY IT KEYS ON RATE, NOT ON A CEILING (§4a). The kernel's own edge signal fires at 98% of the
# segment limit, which at the measured ramp is SEVEN POINT SIX SECONDS of warning. Any actuator keyed
# on the ceiling is too late by construction. The trip is therefore level AND rate (>15% of limit with
# >600 segments/s), or a byte-rate burst — far below the ceiling, on the way up.
#
# WHY IT CAN ACT (§7.2). Detection alone saved nothing three times. The actuator SIGSTOPs the burst
# cohort — newest node workers, never claude.exe, never anything claude/mcp-shaped. SIGSTOP removes
# the demand instantly, is reversible, and cannot lose work; a frozen worker is recoverable, a
# panicked box is not. It is DEFAULT OFF and arms only on CC_SENTINEL_ACT=stop.
#
# WHY NO KILL PATH EXISTS ANYWHERE IN HERE (§4a). macOS ships CONFIG_JETSAM off; the release-kernel
# compressor-exhaustion branch can only harvest IDLE-band processes (measured: ~2 MB of Apple
# daemons), and no_paging_space_action needs ONE process holding >50% of the whole compressor
# (>66 GiB) — structurally untrippable by a fleet of 200 MB workers. Nothing above us will act. That
# is why this exists, and it is also why it must never SIGKILL: we are the only actor, so we must be
# the reversible one.
#
# THE INSTRUMENT'S OWN FAILURE MODES, handled explicitly rather than assumed away:
#   · An unreadable trip-bearing sysctl SKIPS THE TICK — no row. It never renders as 0. This is the
#     exact defect capacity-alarm.sh ate on its launchd PATH (a dead rung reporting the healthy
#     value); "could not measure" must never read as "fine".
#   · Rates divide by MEASURED elapsed seconds, never by the configured interval. Under the storm
#     this exists to catch, a 10 s sleep takes far longer — dividing a 25 s delta by 10 would
#     manufacture a 2.5x trip out of an unchanged machine. The instrument must not invent its subject.
#   · A skipped or stretched tick RESETS the two-consecutive-tick streak. Consecutiveness asserted
#     across a gap is a fabrication.
#   · THE SNAPSHOT NAMES WHAT IT RANKS. Its first shape could not: an argv list cut at `head -80`
#     (truncated in 16 of 18 trips) beside a COMM-only top-30, which renders every Node workload as
#     `node`. Joining the two by pid still left 1-8 of the LARGEST rows unidentified at every trip,
#     so no count of `tsc` — zero or four — could be read off it, and two successive analyses read a
#     confident "tsc = 0" that was an artifact first of the cut and then of the column. An instrument
#     that fires 18 times in an incident without naming its subject is how an unverified cause gets
#     filed. Rank by RSS FIRST, then print the full argv of the rows that ranked (§7-bis(b) of
#     docs/research/machine-lag-and-kitty-2026-08-06.md).
#
# Verdict-free by design: this is a daemon, not a reporting command. It exits 0 on clean shutdown,
# 64 on a usage error, 3 when it cannot read the machine at all on the very first tick.
#
# Seams:  CC_SENTINEL=off (kill switch) · CC_SENTINEL_INTERVAL (10) · CC_SENTINEL_TRIP_SEG_RATE (600)
#         CC_SENTINEL_TRIP_SEG_PCT (15) · CC_SENTINEL_TRIP_CBU_MB (640) · CC_SENTINEL_TRIP_SWAP_MB
#         (1024) · CC_SENTINEL_COOLDOWN (60) · CC_SENTINEL_CENSUS_EVERY (6) · CC_SENTINEL_LOG
#         (moves the snap log with it) · CC_SENTINEL_SNAP · CC_PAGES_DIR · CC_SENTINEL_ACT=stop
#         CC_SENTINEL_SNAP_TOPN (30) · CC_SENTINEL_SNAP_TOPN_FUP (10) · CC_SENTINEL_SNAP_ARGV_MAX
#         (400) · CC_SENTINEL_SNAP_AGG_N (15)
set -uo pipefail

INTERVAL="${CC_SENTINEL_INTERVAL:-10}"
TRIP_SEG_PCT="${CC_SENTINEL_TRIP_SEG_PCT:-15}"
TRIP_SEG_RATE="${CC_SENTINEL_TRIP_SEG_RATE:-600}"
TRIP_CBU_MB="${CC_SENTINEL_TRIP_CBU_MB:-640}"
TRIP_SWAP_MB="${CC_SENTINEL_TRIP_SWAP_MB:-1024}"
COOLDOWN="${CC_SENTINEL_COOLDOWN:-60}"
CENSUS_EVERY="${CC_SENTINEL_CENSUS_EVERY:-6}"
LOG="${CC_SENTINEL_LOG:-$HOME/.claude/logs/compressor-sentinel.jsonl}"
# The snap log DERIVES from LOG so one override moves both — a test that redirects only the JSONL
# would otherwise still append trip snapshots to the operator's live logs.
SNAP="${CC_SENTINEL_SNAP:-${LOG%.jsonl}-snap.log}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/compressor-sentinel.page"
ACT="${CC_SENTINEL_ACT:-off}"
ACT_RSS_KB="${CC_SENTINEL_ACT_RSS_KB:-102400}"   # 100 MB — below this a worker is not the burst
ACT_CAP="${CC_SENTINEL_ACT_CAP:-200}"
FOLLOWUP_N="${CC_SENTINEL_FOLLOWUP_N:-12}"       # 12 x 5 s = the 60 s cooldown, by construction
FOLLOWUP_SEC="${CC_SENTINEL_FOLLOWUP_SEC:-5}"
SNAP_TOPN="${CC_SENTINEL_SNAP_TOPN:-30}"         # trip snapshot: how many RSS ranks carry full argv
SNAP_TOPN_FUP="${CC_SENTINEL_SNAP_TOPN_FUP:-10}" # each follow-up sample: same shape, tighter (x12)
SNAP_ARGV_MAX="${CC_SENTINEL_SNAP_ARGV_MAX:-400}" # per-ROW argv cap in chars; 0 = uncapped
SNAP_AGG_N="${CC_SENTINEL_SNAP_AGG_N:-15}"       # executables in the coarse by-executable total
TICKS=0                                          # 0 = run forever; >0 bounds a smoke/test run

while [ $# -gt 0 ]; do
  if   [ "$1" = "--ticks" ]; then
    TICKS="${2:-}"
    case "$TICKS" in ''|*[!0-9]*) echo "compressor-sentinel.sh: --ticks needs a non-negative integer" >&2; exit 64 ;; esac
    shift
  elif [ "$1" = "--once" ];  then TICKS=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "compressor-sentinel.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_SENTINEL:-on}" = "off" ]; then
  echo "compressor-sentinel: disabled (CC_SENTINEL=off)" >&2
  exit 0
fi

# A non-numeric snapshot seam must never reach awk: there `-v n=abc` becomes 0, an n of 0 renders an
# EMPTY attribution section, and a typo in an env var would silently restore the exact blindness the
# snapshot exists to remove — a section that looks rendered and names nothing. Refuse at startup the
# same way --ticks does, rather than run blind.
# It checks the ENV NAMES, not the internals they feed, so the message names the thing the operator
# can actually act on — an error reading `SNAP_TOPN` sends them looking for a variable that does not
# exist on their side. An unset seam is skipped: the default above already applied, and the defaults
# are numeric by construction.
for _v in CC_SENTINEL_SNAP_TOPN CC_SENTINEL_SNAP_TOPN_FUP CC_SENTINEL_SNAP_ARGV_MAX CC_SENTINEL_SNAP_AGG_N; do
  _x="${!_v:-}"
  [ -n "$_x" ] || continue
  case "$_x" in *[!0-9]*)
    printf 'compressor-sentinel.sh: %s must be a non-negative integer (got "%s")\n' "$_v" "$_x" >&2
    exit 64 ;;
  esac
done

# ── readers ───────────────────────────────────────────────────────────────────────────────────────
# Every one of these returns NON-ZERO rather than a value when the instrument is unreadable. None of
# them has a fallback. That is the whole contract.

# One numeric sysctl. rc 1 when absent, empty, or non-numeric — never a fabricated 0.
read_num_sysctl() { # <name>
  local v
  v="$(sysctl -n "$1" 2>/dev/null)" || return 1
  case "$v" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$v"
}

# vm.swapusage → USED BYTES. Parsed from the unit suffix, never assumed to be M: this is the exact
# term §7.7 calls the swapped-segment count (used ÷ 65536), so a silent 1024x misread here would
# understate the half of the pool that lives on disk.
parse_swap_used_bytes() { # stdin: a vm.swapusage line
  awk '
    { for (i = 1; i < NF; i++) if ($i == "used") { v = $(i + 2); break } }
    END {
      if (v == "") exit 1
      u = substr(v, length(v)); n = substr(v, 1, length(v) - 1) + 0
      m = (u == "G") ? 1073741824 : (u == "M") ? 1048576 : (u == "K") ? 1024 : 0
      if (m == 0) exit 1
      printf "%.0f", n * m
    }'
}

read_swap_used_bytes() {
  local raw
  raw="$(sysctl -n vm.swapusage 2>/dev/null)" || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | parse_swap_used_bytes
}

# ONE vm_stat pass → "<pagesize> <pages_occupied_by_compressor> <compressions> <decompressions>".
# Page size comes from vm_stat's OWN header and is never assumed to be 4096 (it is 16384 on Apple
# silicon; assuming 4096 understates by 4x — capacity-alarm.sh:147 records the same trap).
read_vm_stat() {
  vm_stat 2>/dev/null | awk -F: '
    NR == 1 {
      if (match($0, /page size of [0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); pg = s + 0 }
      next
    }
    {
      k = $1; v = $2
      gsub(/^[ \t]+|[ \t.]+$/, "", v); gsub(/"/, "", k)
      if (v ~ /^[0-9]+$/) d[k] = v + 0
    }
    END {
      if (pg <= 0) exit 1
      if (!("Pages occupied by compressor" in d) || !("Compressions" in d) || !("Decompressions" in d)) exit 1
      printf "%d %d %d %d", pg, d["Pages occupied by compressor"], d["Compressions"], d["Decompressions"]
    }'
}

# ── segment arithmetic (§7.7) ─────────────────────────────────────────────────────────────────────
# The divisor is DERIVED (segment_buffer ÷ pagesize), not the literal 4. Four is only correct at a
# 16 KiB page size — true on this box (65536/16384), false on a 4 KiB one, where the right answer is
# 16 and the literal would understate in-core segments by 4x.
segs_in_core() { # <pages_occupied> <pagesize> <segment_buffer_size>
  awk -v p="$1" -v pg="$2" -v buf="$3" 'BEGIN {
    if (pg <= 0 || buf <= 0 || buf < pg) exit 1
    printf "%d", p / (buf / pg)
  }'
}

# EXACT, not an estimate: swap is allocated in one-segment (64 KiB) compressed chunks.
segs_swapped() { # <swap_used_bytes> <segment_buffer_size>
  awk -v b="$1" -v buf="$2" 'BEGIN { if (buf <= 0) exit 1; printf "%d", b / buf }'
}

# ── the trip predicate ────────────────────────────────────────────────────────────────────────────
# Prints the breach reason and returns 0 when THIS SAMPLE breaches; rc 1 when clear. Pure: every
# threshold arrives as a variable, so the suite can drive it without a machine.
#
# All three arms are RATES normalised to the configured interval. The brief's "640 MB/tick" and
# "1 GB/tick" are 64 MB/s and 102.4 MB/s at the 10 s default — which is exactly how §7.1 states the
# ramp ("on ramp (>64 MB/s sustained)"). Comparing raw per-tick deltas would let a tick stretched by
# the storm manufacture a trip on an unchanged machine.
classify_breach() { # <seg_est> <seg_limit> <seg_rate_per_s> <dcbu_bytes_per_s> <dswap_bytes_per_s>
  awk -v seg="$1" -v lim="$2" -v rate="$3" -v dcbu="$4" -v dswap="$5" \
      -v pct="$TRIP_SEG_PCT" -v rmin="$TRIP_SEG_RATE" -v cmb="$TRIP_CBU_MB" -v smb="$TRIP_SWAP_MB" \
      -v iv="$INTERVAL" '
    BEGIN {
      if (iv <= 0) exit 1
      n = 0; why = ""
      # Level AND rate. Level alone is a standing state (this box idles well under 15%); rate alone
      # fires on every benign build. §6 discriminator 1+2: it is the conjunction that has no observed
      # benign counterpart in 102 h.
      if (lim > 0 && seg > lim * pct / 100 && rate > rmin) { why = "seg"; n++ }
      if (dcbu  > cmb * 1048576 / iv) { why = why (n ? "+" : "") "cbu";  n++ }
      if (dswap > smb * 1048576 / iv) { why = why (n ? "+" : "") "swap"; n++ }
      if (n == 0) exit 1
      print why
    }'
}

# ── node census (every CENSUS_EVERY ticks) ────────────────────────────────────────────────────────
# → "<node_count> <orphans> <node_rss_mb>|<pid pid ...>". The pid list is what makes the actuator
# able to say "new since 60 s ago" — the burst cohort — instead of stopping the whole fleet.
# -ww because macOS ps truncates a column to its width, and a truncated comm silently drops matches.
census() {
  ps -axwwo pid=,ppid=,rss=,comm= 2>/dev/null | awk '
    $1 ~ /^[0-9]+$/ {
      n = split($4, p, "/"); base = p[n]
      if (base !~ /^node/) next
      c++; rss += $3; if ($2 == 1) orph++
      pids = pids " " $1
    }
    END { printf "%d %d %d|%s", c + 0, orph + 0, rss / 1024, pids }'
}

# ── actuator target selection ─────────────────────────────────────────────────────────────────────
# stdin: `ps -axwwo pid=,rss=,comm=,args=`. Prints "<pid> <rss_kb> <comm>" per line, capped.
#
# Deliberately UNDER-inclusive: the cohort test is the EXECUTABLE NAME (comm basename ~ /^node/),
# never the argv. Matching argv would sweep in any shell whose command line merely mentions node, and
# the cost asymmetry is total — a missed worker costs one more tick of ramp, a wrongly-stopped
# process costs the operator's session. For the same reason claude.exe/claude and anything
# claude/mcp-shaped are excluded twice over (comm and args), even though the comm filter alone
# already excludes claude.exe.
select_stop_targets() { # <prev_census_pids> <rss_floor_kb> <cap>
  awk -v prev=" $1 " -v floor="$2" -v cap="$3" '
    $1 ~ /^[0-9]+$/ {
      pid = $1; rss = $2 + 0; comm = $3
      args = ""; for (i = 4; i <= NF; i++) args = args " " $i
      n = split(comm, p, "/"); base = p[n]
      if (base !~ /^node/) next
      if (base == "claude.exe" || base == "claude") next
      if (args ~ /claude/ || args ~ /mcp/) next
      if (rss <= floor) next
      if (index(prev, " " pid " ") > 0) next          # present at the last census ⇒ not the burst
      if (++k > cap) exit
      printf "%s %s %s\n", pid, rss, base
    }'
}

# ── trip capture: rank first, then attribute ──────────────────────────────────────────────────────
# §7-bis(b) of docs/research/machine-lag-and-kitty-2026-08-06.md is the postmortem of what these
# replaced, and it is why BOTH of the old sections are gone rather than widened:
#   · `--- argv (node|chrom|…, head -80) ---` hit the cut in 16 of 18 trips. A `head` over a
#     NAME-filtered, unranked list drops whole PROCESSES, and a dropped process is a lookup MISS that
#     reads as an ABSENCE — the filter was a second blindness besides, since nothing outside its six
#     names could appear at all.
#   · `--- top by memory ---` printed COMM only, so every Node workload rendered as `node`: tsc,
#     next-server and an MCP chain were indistinguishable.
# The composition is now inverted. What bounds a section is a RANK, in the exact quantity the
# incident is about, so what falls off the end is provably smaller than everything that stays; the
# old bound was a line count over an unranked list, where what fell off was whatever `ps` happened
# to emit last. `pgrep -f` remains no substitute for `ps` here — macOS matches it against a TRUNCATED
# argv (capacity-alarm.sh:231 measured it returning 0 against a real 8) — and neither renderer pipes
# to `head`, which under `set -o pipefail` would SIGPIPE the producer and promote the pipeline to 141.

# stdin: `ps -Awwo pid=,ppid=,rss=,pcpu=,args=` → the <n> highest-RSS rows, argv intact.
#
# Only <n> rows are ever held, by bounded insertion. Buffering the whole process table in order to
# sort it would make the instrument allocate in proportion to the fleet it is measuring, at the one
# moment memory is the scarce thing.
#
# The four leading columns are matched as a PREFIX and the remainder taken verbatim rather than
# rejoined from $5..$NF, because rejoining collapses runs of whitespace INSIDE argv and so silently
# rewrites the record. The fourth column is matched as "any non-blank" rather than [0-9.]+ so that a
# locale rendering %CPU as `0,0` cannot drop every row on the floor.
#
# argv is capped per ROW at <amax> chars (0 = uncapped) and the cut is STAMPED with how much it
# dropped. That is not the head -80 defect returning by another door: that one dropped whole
# processes silently, this shortens ONE named row's tail and says by exactly how much. Agent briefs
# travel in argv (memory pgrep-f-matches-agent-briefs), so uncapped rows run to tens of KB each,
# 13 snapshots per trip, into a 25 MiB rotation.
top_by_rss() { # <n> <argv_max_chars>
  awk -v n="$1" -v amax="$2" '
    match($0, /^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+[^ \t]+[ \t]+/) {
      rss = $3 + 0
      args = substr($0, RSTART + RLENGTH)
      if (amax > 0 && length(args) > amax)
        args = substr(args, 1, amax) sprintf("…[+%d chars]", length(args) - amax)
      row = sprintf("%7s %7s %10d %6s  %s", $1, $2, rss, $4, args)
      if (k < n)           { pos = ++k }
      else if (rss > r[k]) { pos = k }
      else                 { next }
      while (pos > 1 && r[pos - 1] < rss) { r[pos] = r[pos - 1]; l[pos] = l[pos - 1]; pos-- }
      r[pos] = rss; l[pos] = row
    }
    END { for (i = 1; i <= k; i++) print l[i] }'
}

# stdin: `ps -Awwo rss=,comm=` → the <n> executables holding the most RSS, with their counts.
#
# It takes its OWN ps rather than reusing the rows above: comm is the last field there, so everything
# past the RSS column is the executable path verbatim, spaces included (`…/Google Chrome for
# Testing`). With argv trailing instead, no parseable boundary exists.
#
# Coarse BY CONSTRUCTION — it groups on the executable, the very column §7-bis convicted — so it is
# labelled a total and never attribution. It is here because the ranked section above cannot see the
# one shape the old unranked list caught by accident: forty workers at 180 MB each outweigh any
# single row and appear in none of them. Removing that list without this would be a net loss.
rss_by_exe() { # <n>
  awk -v n="$1" '
    match($0, /^[ \t]*[0-9]+[ \t]+/) {
      exe = substr($0, RSTART + RLENGTH)
      c = split(exe, p, "/"); base = p[c]
      sum[base] += $1 + 0; cnt[base]++
    }
    END {
      for (b in sum) {
        v = sum[b]
        if (m < n)          { pos = ++m }
        else if (v > sv[m]) { pos = m }
        else                { continue }
        while (pos > 1 && sv[pos - 1] < v) { sv[pos] = sv[pos - 1]; sb[pos] = sb[pos - 1]; pos-- }
        sv[pos] = v; sb[pos] = b
      }
      for (i = 1; i <= m; i++) printf "%10.1f MB  x%-4d %s\n", sv[i] / 1024, cnt[sb[i]], sb[i]
    }'
}

# One sample of attribution. The follow-ups render it too, at a tighter rank: under the old shape
# those twelve samples were COMM-only, which made the part of the record that WATCHES the ramp the
# blindest part of it — and a process born after the trip appeared in no section at all.
# <agg_n> 0 omits the coarse total, which is a standing shape rather than a ramp.
render_attribution() { # <top_n> <argv_max_chars> <agg_n>
  local rows exe
  rows="$(ps -Awwo pid=,ppid=,rss=,pcpu=,args= 2>/dev/null)" || rows=""
  if [ -z "$rows" ]; then
    # An empty section would read as an idle machine. Say which of the two it is: this is the same
    # contract the readers hold, where "could not measure" must never render as the healthy value.
    printf '\n--- top %s by RSS ---\n(NO ROWS — ps was unreadable. A blind instrument, not an idle box.)\n' "$1"
  else
    printf '\n--- top %s by RSS, full argv (a RANK bound — nothing below is a line cut) ---\n' "$1"
    printf '    PID    PPID     RSS_KB   %%CPU  ARGV\n'
    printf '%s\n' "$rows" | top_by_rss "$1" "$2"
  fi

  [ "$3" -gt 0 ] || return 0
  exe="$(ps -Awwo rss=,comm= 2>/dev/null)" || exe=""
  if [ -z "$exe" ]; then
    printf '\n--- RSS by executable ---\n(NO ROWS — ps was unreadable.)\n'
  else
    printf '\n--- RSS by executable, top %s (COARSE total: shared pages double-count, so an upper bound. The argv above is the attribution) ---\n' "$3"
    printf '%s\n' "$exe" | rss_by_exe "$3"
  fi
}

snapshot_trip() { # <ts> <why> <headline>
  {
    printf '\n═══ TRIP %s  why=%s ═══\n%s\n' "$1" "$2" "$3"
    render_attribution "$SNAP_TOPN" "$SNAP_ARGV_MAX" "$SNAP_AGG_N"
    printf '\n--- vm_stat ---\n'
    vm_stat 2>/dev/null
  } >> "$SNAP" 2>/dev/null || true
}

# Twelve more top-RSS reads at 5 s. Run in the BACKGROUND, and that is a design decision, not a
# convenience: 12 x 5 s blocking would blind the JSONL for a full minute starting at the exact moment
# the ramp becomes interesting — and §6 discriminator 4 makes a row GAP a distress signal in its own
# right, so a self-inflicted gap would poison the one channel the post-mortem trusts most.
snapshot_followup() {
  local i=0
  while [ "$i" -lt "$FOLLOWUP_N" ]; do
    sleep "$FOLLOWUP_SEC"
    i=$((i + 1))
    {
      printf '\n--- follow-up %s/%s  %s ---\n' "$i" "$FOLLOWUP_N" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      render_attribution "$SNAP_TOPN_FUP" "$SNAP_ARGV_MAX" 0
    } >> "$SNAP" 2>/dev/null || true
  done
}

# The page envelope, same shape as capacity-alarm.sh:609-643 (epoch, headline, detail, re-run) and
# one fixed slug so no cadence can accumulate pages.
#
# IT DOES NOT SELF-CLEAR, and that is the one place it deliberately diverges from capacity-alarm's
# page contract. That page asserts a LEVEL, so a cleared level must retract it. This one records an
# EDGE: by the time anyone reads it the ramp is usually over, but the trip still happened and the
# page is the only pointer to the snapshot that explains it. Retracting it would delete the receipt.
write_page() { # <ts> <why> <headline> <detail>
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  {
    date +%s 2>/dev/null || echo 0
    printf 'compressor-sentinel TRIP (%s) — %s\n' "$2" "$3"
    printf '%s\n' "$4"
    printf 'This is the axis three kernel panics died on. The kernel edge leaves 7.6 s; this fired\n'
    printf 'on RATE, well below it. Actuator: %s.\n' "$ACT"
    printf 'snapshot: %s\n' "$SNAP"
    printf 'samples:  %s\n' "$LOG"
    printf 're-run:   %s\n' "$0"
  } > "$PAGE" 2>/dev/null || true
}

# ── main loop ─────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG")" "$(dirname "$SNAP")" 2>/dev/null || true

FOLLOWUP_PID=""
# shellcheck disable=SC2329  # invoked indirectly, by the trap below.
cleanup() {
  [ -n "$FOLLOWUP_PID" ] && kill "$FOLLOWUP_PID" 2>/dev/null
  exit 0
}
trap cleanup TERM INT

PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""
# THREE SEPARATE KEYS, not one comma-joined field. The first draft emitted `"n":8,2,3404` — three
# bare values under one key, which no JSON parser accepts, so a single census would have poisoned
# every consumer of the whole file. capacity-alarm.sh:560 records the identical defect (`"est_room_
# sessions":?`) and the identical reason it survived review: a regex test for one field never
# requires the surrounding document to parse. Caught here by a 3-tick smoke, not by reading.
CENSUS_PIDS=""; CENSUS_N="null"; CENSUS_ORPH="null"; CENSUS_RSS="null"
STREAK=0; COOLDOWN_UNTIL=0; TICK=0; ROWS=0

while :; do
  TICK=$((TICK + 1))
  NOW="$(date +%s)"

  # Required — the trip cannot be evaluated without any of these, so an unreadable one skips the
  # whole tick. No row. A row with a fabricated 0 in it is worse than no row, because it reads green.
  SKIP=""
  VMS="$(read_vm_stat)"           || SKIP="vm_stat"
  SWAP_B="$(read_swap_used_bytes)" || SKIP="${SKIP:-vm.swapusage}"
  SEG_LIMIT="$(read_num_sysctl vm.compressor_segment_limit)" || SKIP="${SKIP:-vm.compressor_segment_limit}"
  SEG_BUF="$(read_num_sysctl vm.compressor_segment_buffer_size)" || SKIP="${SKIP:-vm.compressor_segment_buffer_size}"
  CBU="$(read_num_sysctl vm.compressor_bytes_used)" || SKIP="${SKIP:-vm.compressor_bytes_used}"

  if [ -n "$SKIP" ]; then
    printf '%s compressor-sentinel: SKIP tick %s — unreadable %s (no row emitted; not a 0)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICK" "$SKIP" >&2
    # A gap breaks consecutiveness and invalidates every baseline: the next delta would span two
    # intervals and the next streak would be asserted across a hole.
    PREV_T=""; PREV_SEG=""; PREV_CBU=""; PREV_SWAP=""; PREV_CMP=""; PREV_DCMP=""; STREAK=0
    [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
    sleep "$INTERVAL"
    continue
  fi

  PAGESZ="${VMS%% *}"; VMS_R="${VMS#* }"
  OCCUP="${VMS_R%% *}"; VMS_R="${VMS_R#* }"
  COMPRESSIONS="${VMS_R%% *}"; DECOMPRESSIONS="${VMS_R##* }"

  SEG_I="$(segs_in_core "$OCCUP" "$PAGESZ" "$SEG_BUF")" || SEG_I=""
  SEG_S="$(segs_swapped "$SWAP_B" "$SEG_BUF")" || SEG_S=""
  if [ -z "$SEG_I" ] || [ -z "$SEG_S" ]; then
    printf '%s compressor-sentinel: SKIP tick %s — segment arithmetic unresolvable\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TICK" >&2
    PREV_T=""; PREV_SEG=""; STREAK=0
    [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
    sleep "$INTERVAL"; continue
  fi
  SEG_EST=$((SEG_I + SEG_S))
  SEG_PCT="$(awk -v a="$SEG_EST" -v b="$SEG_LIMIT" 'BEGIN{ if (b <= 0) exit 1; printf "%.2f", 100*a/b }')" || SEG_PCT=""

  # Diagnostic-only sysctls. These do NOT gate the tick: they discriminate WHICH mechanism is running
  # (§4a — incompressible raw-store vs sparse-segment fragmentation), which decides the remedy but
  # not the trip. A build without them must still be guarded, so they render as JSON null — an
  # honest absence, not the fabricated 0 the required set refuses.
  INB="$(read_num_sysctl vm.compressor_input_bytes)"      || INB=""
  CPB="$(read_num_sysctl vm.compressor_compressed_bytes)" || CPB=""
  WKF="$(read_num_sysctl vm.wk_compression_failures)"     || WKF=""
  L4F="$(read_num_sysctl vm.lz4_compression_failures)"    || L4F=""
  FAILS=""
  [ -n "$WKF" ] && [ -n "$L4F" ] && FAILS=$((WKF + L4F))

  # ── deltas, normalised by MEASURED elapsed seconds ──────────────────────────────────────────────
  D_SEG="null"; D_CBU="null"; D_SWAP="null"; D_CMP="null"; D_DCMP="null"
  SEG_RATE="null"; CBU_RATE="null"; SWAP_RATE="null"; ELAPSED="null"
  HAVE_RATES=0
  if [ -n "$PREV_T" ] && [ "$NOW" -gt "$PREV_T" ]; then
    ELAPSED=$((NOW - PREV_T))
    D_SEG=$((SEG_EST - PREV_SEG))
    D_CBU=$((CBU - PREV_CBU))
    D_SWAP=$((SWAP_B - PREV_SWAP))
    D_CMP=$((COMPRESSIONS - PREV_CMP))
    D_DCMP=$((DECOMPRESSIONS - PREV_DCMP))
    SEG_RATE="$(awk -v d="$D_SEG" -v e="$ELAPSED" 'BEGIN{printf "%.1f", d/e}')"
    CBU_RATE="$(awk -v d="$D_CBU" -v e="$ELAPSED" 'BEGIN{printf "%.0f", d/e}')"
    SWAP_RATE="$(awk -v d="$D_SWAP" -v e="$ELAPSED" 'BEGIN{printf "%.0f", d/e}')"
    HAVE_RATES=1
  fi

  # ── census every CENSUS_EVERY ticks ─────────────────────────────────────────────────────────────
  if [ $((TICK % CENSUS_EVERY)) -eq 0 ]; then
    CRAW="$(census)"
    if [ -n "$CRAW" ]; then
      CENSUS_PIDS="${CRAW#*|}"
      CHEAD="${CRAW%%|*}"
      CENSUS_N="${CHEAD%% *}"; CREST="${CHEAD#* }"
      CENSUS_ORPH="${CREST%% *}"; CENSUS_RSS="${CREST##* }"
      : "${CENSUS_N:=null}" "${CENSUS_ORPH:=null}" "${CENSUS_RSS:=null}"
    fi
  fi

  # ── the row ─────────────────────────────────────────────────────────────────────────────────────
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ROW="$(printf '{"ts":"%s","t":%s,"el":%s,"seg":%s,"segi":%s,"segs":%s,"lim":%s,"pct":%s,"dseg":%s,"srate":%s,"cbu":%s,"dcbu":%s,"crate":%s,"swap":%s,"dswap":%s,"wrate":%s,"dcmp":%s,"ddec":%s,"inb":%s,"cpb":%s,"fail":%s,"n":%s,"orph":%s,"nrss":%s,"strk":%s}' \
    "$TS" "$TICK" "$ELAPSED" "$SEG_EST" "$SEG_I" "$SEG_S" "$SEG_LIMIT" "${SEG_PCT:-null}" \
    "$D_SEG" "$SEG_RATE" "$CBU" "$D_CBU" "$CBU_RATE" "$SWAP_B" "$D_SWAP" "$SWAP_RATE" \
    "$D_CMP" "$D_DCMP" "${INB:-null}" "${CPB:-null}" "${FAILS:-null}" \
    "$CENSUS_N" "$CENSUS_ORPH" "$CENSUS_RSS" "$STREAK")"
  printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
  ROWS=$((ROWS + 1))

  # ── breach → streak → trip ──────────────────────────────────────────────────────────────────────
  WHY=""
  if [ "$HAVE_RATES" = 1 ]; then
    WHY="$(classify_breach "$SEG_EST" "$SEG_LIMIT" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")" || WHY=""
  fi
  if [ -n "$WHY" ]; then STREAK=$((STREAK + 1)); else STREAK=0; fi

  if [ -n "$WHY" ] && [ "$STREAK" -ge 2 ] && [ "$NOW" -ge "$COOLDOWN_UNTIL" ]; then
    HEAD_LINE="$(printf 'segments %s of %s (%s%%) · %s seg/s · compressor +%s B/s · swap +%s B/s' \
      "$SEG_EST" "$SEG_LIMIT" "${SEG_PCT:-?}" "$SEG_RATE" "$CBU_RATE" "$SWAP_RATE")"
    printf '%s compressor-sentinel: TRIP why=%s — %s\n' "$TS" "$WHY" "$HEAD_LINE" >&2
    snapshot_trip "$TS" "$WHY" "$HEAD_LINE"
    write_page "$TS" "$WHY" "$HEAD_LINE" "$ROW"

    if [ "$ACT" = "stop" ]; then
      STOPPED=0
      TARGETS="$(ps -axwwo pid=,rss=,comm=,args= 2>/dev/null \
                 | select_stop_targets "$CENSUS_PIDS" "$ACT_RSS_KB" "$ACT_CAP")"
      while read -r spid srss scomm; do
        [ -n "$spid" ] || continue
        # SIGSTOP only. Never SIGKILL — we are the only actor above the kernel here (§4a: jetsam is
        # off and no_paging_space_action is untrippable by a fleet), so we must be the reversible one.
        if kill -STOP "$spid" 2>/dev/null; then
          STOPPED=$((STOPPED + 1))
          printf 'SIGSTOP pid=%s rss_kb=%s comm=%s\n' "$spid" "$srss" "$scomm" >> "$SNAP" 2>/dev/null || true
        fi
      done <<< "$TARGETS"
      printf 'actuator: SIGSTOPped %s process(es) (cap %s, floor %s kB)\n' \
        "$STOPPED" "$ACT_CAP" "$ACT_RSS_KB" >> "$SNAP" 2>/dev/null || true
    else
      printf 'actuator: DISARMED (CC_SENTINEL_ACT=%s) — detection only\n' "$ACT" >> "$SNAP" 2>/dev/null || true
    fi

    # One follow-up run at a time; it self-terminates in 60 s, which is the cooldown.
    if [ -z "$FOLLOWUP_PID" ] || ! kill -0 "$FOLLOWUP_PID" 2>/dev/null; then
      snapshot_followup &
      FOLLOWUP_PID=$!
    fi
    COOLDOWN_UNTIL=$((NOW + COOLDOWN))
    STREAK=0
  fi

  PREV_T="$NOW"; PREV_SEG="$SEG_EST"; PREV_CBU="$CBU"; PREV_SWAP="$SWAP_B"
  PREV_CMP="$COMPRESSIONS"; PREV_DCMP="$DECOMPRESSIONS"

  [ "$TICKS" -gt 0 ] && [ "$TICK" -ge "$TICKS" ] && break
  sleep "$INTERVAL"
done

# KILL the follow-up on exit, never wait for it. A bounded run (--ticks, i.e. the smoke and the
# suite) that tripped on its last tick would otherwise BLOCK for the full 60 s of follow-up
# snapshots. The follow-up exists to capture a ramp we are still watching; once the sentinel is
# leaving, the capture has no consumer.
if [ -n "$FOLLOWUP_PID" ]; then kill "$FOLLOWUP_PID" 2>/dev/null; wait 2>/dev/null; fi
# Zero rows on a bounded run means the machine was unreadable for every tick — that is a broken
# instrument, and it must not exit 0 into an activation script that would read success.
[ "$ROWS" -gt 0 ] || exit 3
exit 0
