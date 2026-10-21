#!/usr/bin/env bats
# shellcheck disable=SC2016  # stub bodies carry literal $* / $0 on purpose
# kitty-hygiene.sh + scripts/lib/kitty-naps.py + scripts/lib/kitty-fd-headroom.py (LR_SUSTAINED_LOAD
# W7; design docs/research/lr-sustained-load-2026-10-20/impl/B8-kitty-hygiene.md §6 and its reviews).
#
# NOTHING HERE TOUCHES A REAL KITTY. defaults, ps, lsof, log, codesign, PlistBuddy, stat, sysctl,
# ioreg, lsappinfo, kitten and band.py are stubs under $BATS_TEST_TMPDIR; the "kitty" is a `sleep`
# this file starts (so `kill -0` sees it alive) and the ps stub's census names it. The subject runs
# under /bin/bash 3.2 and /usr/bin/python3, the interpreters an operator shell and launchd give it.
# The RunningBoard fixtures are real lines (10-19 incident, 10-20 30-minute capture of kitty 853, the
# keyed Dia 1037), trimmed to the pid.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/kitty-hygiene.sh"
  NAPS="$REPO/scripts/lib/kitty-naps.py"
  FDH="$REPO/scripts/lib/kitty-fd-headroom.py"
  T="$BATS_TEST_TMPDIR"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export KH_T="$T" TMPDIR="$T/tmp" LR_STATE_DIR="$T/lr" LR_RECON_ROOT="$T/lr/recon"
  export CC_KH_SAMPLE_DIR="$BATS_TEST_TMPDIR/samples"
  mkdir -p "$HOME" "$TMPDIR" "$T/bin" "$T/mtime" "$T/kitty.app/Contents/MacOS"
  : > "$T/kitty.app/Contents/Info.plist"; : > "$T/kitty.app/Contents/MacOS/kitty"
  export CC_KITTY_APP="$T/kitty.app" CC_KH_PLIST="$T/net.kovidgoyal.kitty.plist"
  : > "$CC_KH_PLIST"
  export CC_KH_TIMEOUT_BIN=""          # stock macOS: no timeout(1), so the perl-alarm leg is what runs
  export CC_KH_PYTHON=/usr/bin/python3
  # generous bounds at 15-40/core: a test that is ABOUT a bound lowers its own; a fired one reads ?
  export CC_KH_PS_TIMEOUT_S=60 CC_KH_DEFAULTS_TIMEOUT_S=60 CC_KH_BAND_TIMEOUT_S=60 CC_KH_LSOF_TIMEOUT_S=60
  unset CC_KITTY_HYGIENE CC_KH_CALLER
  sleep 600 & KP=$!; export KP
  NOW="$(date +%s)"; START=$((NOW - 300))

  stub() { printf '#!/bin/bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
  # defaults: .mode on | absent | err | off; logs argv
  stub defaults 'echo "$*" >> "$0.log"
case "$(cat "$0.mode" 2>/dev/null || echo on)" in
  on) echo 1 ;; off) echo 0 ;;
  absent) echo "The domain/default pair of (net.kovidgoyal.kitty, NSAppSleepDisabled) does not exist" >&2; exit 1 ;;
  *) echo "cfprefsd: Connection invalid" >&2; exit 1 ;;
esac'
  # ps: the census, a per-pid lstart (in the operator locale unless LC_ALL=C — review S11), ps -M, zombies
  stub ps 'echo "TZ=${TZ:-} LC_ALL=${LC_ALL:-} $*" >> "$0.log"
case "$*" in
  "-axo pid=,ppid=,lstart=,args=") [ -f "$0.rc" ] && exit "$(cat "$0.rc")"; cat "$0.census" ;;
  "-p "*" -o lstart=") e="$(awk -v p="$2" "\$1 == p { print \$2 }" "$0.starts")"; [ -n "$e" ] || exit 1
     if [ "${LC_ALL:-}" = C ]; then LC_ALL=C /bin/date -u -r "$e" "+%a %b %e %T %Y"
     else LC_ALL=C /bin/date -u -r "$e" "+%a %e %b %T %Y"; fi ;;
  "-M -p "*) printf "USER PID TT %%CPU STAT PRI STIME UTIME COMMAND\nme %s ?? 0.0 S %s 0:00.01 0:00.01 kitty\n" "$3" "$(cat "$0.thr" 2>/dev/null || echo 47T)" ;;
  "-axo ppid=,stat=") cat "$0.zombies" 2>/dev/null; exit 0 ;;
  *) exit 64 ;;
esac'
  stub lsof '[ -f "$0.sleep" ] && sleep "$(cat "$0.sleep")"
n="$(cat "$0.n" 2>/dev/null || echo 40)"; u="$(cat "$0.unix" 2>/dev/null || echo 2)"; x="$(cat "$0.extra" 2>/dev/null || echo 50)"
echo "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"
i=0; while [ $i -lt $n ]; do t=CHR; [ $i -lt $u ] && t=unix; echo "kitty $4 me ${i}u $t 0x0 0t0 0 x"; i=$((i + 1)); done
case "$*" in *"-d 0-65535"*) ;; *) i=0; while [ $i -lt $x ]; do echo "kitty $4 me txt REG 1 2 3 /lib"; i=$((i + 1)); done ;; esac'
  stub stat 'f="$KH_T/mtime/$(basename "$3")"; [ -f "$f" ] && cat "$f" || exit 1'
  stub PlistBuddy 'cat "$0.ver" 2>/dev/null || echo 0.49.2'
  stub codesign 'echo "TeamIdentifier=NTY7FVCEKP" >&2; if [ -f "$0.adhoc" ]; then echo "Signature=adhoc" >&2; else echo "Signature size=8972" >&2; fi'
  stub sysctl 'case "$2" in vm.loadavg) echo "{ 150.00 140.00 130.00 }" ;; hw.ncpu) echo 10 ;; esac'
  stub ioreg 'echo "\"CGSSessionScreenIsLocked\"=No"'
  stub lsappinfo 'case "$1" in front) echo ASN:0x1 ;; info) echo "\"LSDisplayName\"=\"kitty\"" ;; esac'
  stub kitten 'echo "$*" >> "$0.log"; exit "$(cat "$0.rc" 2>/dev/null || echo 0)"'
  stub log 'echo "$*" >> "$0.log"
case "$*" in
  *"eventMessage CONTAINS"*) n=$(( $(cat "$0.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$0.n"
     [ -f "$0.hang" ] && sleep 20
     [ "$n" = 1 ] && [ -f "$0.slice" ] && cat "$0.slice"
     exit "$(cat "$0.slice-rc" 2>/dev/null || echo 0)" ;;
  *) [ -f "$0.retention" ] && cat "$0.retention"; exit 0 ;;
esac'
  printf '2026-10-19 21:00:00.000 Df runningboardd[637:1] [com.apple.runningboard:ttl] x\n' > "$T/bin/log.retention"
  printf 'import os, sys\nv = open(os.environ["KH_T"] + "/band.val").read().strip()\nprint(v)\nsys.exit(0 if v.isdigit() else 1)\n' > "$T/band.py"
  echo 31 > "$T/band.val"
  for b in defaults ps lsof stat PlistBuddy codesign sysctl ioreg lsappinfo kitten log; do
    u="$(printf '%s' "$b" | tr '[:lower:]' '[:upper:]')"
    case "$b" in PlistBuddy) u=PLISTBUDDY ;; esac
    export "CC_KH_${u}_BIN=$T/bin/$b"
  done
  export CC_KH_BAND_PY="$T/band.py"
  # the green state: key on and written before this kitty started, one main kitty, a 0.49.2 bundle
  # older than the process, a developer signature, band 31
  census "$KP 1 $START $T/kitty.app/Contents/MacOS/kitty"
  echo "$((START - 100))" > "$T/mtime/net.kovidgoyal.kitty.plist"
  echo "$((START - 1000))" > "$T/mtime/Info.plist"; echo "$((START - 1000))" > "$T/mtime/kitty"
  # forbidden actuators on PATH: any call is logged (T9); kill is a builtin, so the lint covers it
  for b in open brew osascript launchctl pkill killall kill taskpolicy; do
    printf '#!/bin/bash\necho "%s $*" >> "%s/forbidden.log"\n' "$b" "$T" > "$T/bin/$b"; chmod +x "$T/bin/$b"
  done
  export PATH="$T/bin:$PATH"
}

teardown() { kill "$KP" 2>/dev/null || true; [ -z "${BG:-}" ] || kill "$BG" 2>/dev/null || true; }

census() { # <"pid ppid epoch exe [args…]">… → the ps stub's census and per-pid start table
  : > "$T/bin/ps.census"; : > "$T/bin/ps.starts"
  local row pid ppid e rest
  for row in "$@"; do
    # shellcheck disable=SC2086  # the row is word-split into its fields on purpose
    set -- $row; pid="$1" ppid="$2" e="$3"; shift 3; rest="$*"
    printf '%6s %6s %s %s\n' "$pid" "$ppid" "$(LC_ALL=C /bin/date -u -r "$e" '+%a %b %e %T %Y')" "$rest" >> "$T/bin/ps.census"
    echo "$pid $e" >> "$T/bin/ps.starts"
  done
}
st() { run /bin/bash "$SUT" status "$@"; }
line() { printf '%s\n' "$output" | grep -E "^$1=" | head -1; }

# ── fixtures: real runningboardd lines (`log show --style compact`), trimmed to the pid ──────────
# kitty 853, 10-19 21:54-23:09 CDT: role lines + adapter acquisitions (the 713 s focal nap)
fx_incident() { cat <<'FX'
2026-10-19 21:54:50.140 Df runningboardd[637:8904f18] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-408377 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Inactive" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventDiskThrottle" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventSuppressedCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventLowPriorirtyCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventBackgroundSockets" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier0" sourceEnvironment:<…>
2026-10-19 21:54:53.969 Df runningboardd[637:88fe386] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-19 22:56:05.001 Df runningboardd[637:905cec6] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-410653 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier4" sourceEnvironment:"(null)">
	]>
2026-10-19 22:56:05.018 Df runningboardd[637:905cec6] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-410658 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Inactive" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventDiskThrottle" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventSuppressedCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventLowPriorirtyCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventBackgroundSockets" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier0" sourceEnvironment:<…>
2026-10-19 22:56:48.503 Df runningboardd[637:906ee40] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-410724 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier5" sourceEnvironment:"(null)">
	]>
2026-10-19 23:08:40.861 Df runningboardd[637:915f04f] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-411608 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier4" sourceEnvironment:"(null)">
	]>
2026-10-19 23:08:41.004 Df runningboardd[637:916a2dd] [com.apple.runningboard:ttl] Acquiring assertion targeting [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] from originator [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] with description <RBSAssertionDescriptor| "AppNap adapter assertion" ID:637-853-411630 target:853 attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Inactive" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventDiskThrottle" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventSuppressedCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventLowPriorirtyCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventBackgroundSockets" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier0" sourceEnvironment:<…>
2026-10-19 23:08:49.992 Df runningboardd[637:9163f0a] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
FX
}
# Dia 1037 (NSAppSleepDisabled set): role lines + one state dump listing its assertions, no adapter
fx_dia() { cat <<'FX'
2026-10-19 22:58:49.381 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 17
	<RBAssertion| identifier:637-605-720 target:[app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] explanation:"foregroundApp:1037" active originator:[osservice<com.apple.coreservices.launchservicesd>:605] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom prevSus runningReason:20248 legRes:0 doms:com.apple.launchservicesd:RoleUserInteractiveNonFocal invOnConds:(null)> processState:<RBProcessState| role:UserInteractiveNonFocal> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.launchservicesd" name:"RoleUserInteractiveNonFocal" sourceEnvironment:"(null)">
	]>
2026-10-19 22:58:49.382 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 25
	<RBAssertion| identifier:637-633-410670 target:[app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] explanation:"FUSBProcessWindowState: occluded" active originator:[osservice<com.apple.WindowServer(88)>:633] transientState:<RBAssertionTransientState| policies:[
	
	] tags:[
	SupportsBackgroundAudio> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dreldom prevSus runningReason:10000 legRes:0 doms:com.apple.fuseboard:Occluded invOnConds:(null)> processState:<RBProcessState| role:UserInteractiveNonFocal> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.fuseboard" name:"Occluded" sourceEnvironment:"(null)">,
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>
	]>
2026-10-19 23:08:49.879 Df runningboardd[637:915ec8f] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveFocal
2026-10-19 23:08:55.536 Df runningboardd[637:916a2dd] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveNonFocal
2026-10-19 23:09:43.204 Df runningboardd[637:916ef04] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveFocal
2026-10-19 23:09:47.942 Df runningboardd[637:916ef04] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveNonFocal
2026-10-19 23:09:51.334 Df runningboardd[637:916ef04] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveFocal
2026-10-19 23:10:16.581 Df runningboardd[637:915f04f] [com.apple.runningboard:ttl] [app<application.company.thebrowser.dia.1979819648.1979819653(501)>:1037] Set darwin role to: UserInteractiveNonFocal
FX
}
# kitty 853, 10-20 13:25-13:55 CDT (review capture ls30): role lines + its HELD adapter in a dump,
# beside the adapter of an xpcservice kitty HOSTS ("([app<…>:853])"), which is not kitty's own
fx_enrolled() { cat <<'FX'
2026-10-20 13:25:12.855 Df runningboardd[637:dd22cef] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:32:37.834 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 4
	<RBAssertion| identifier:637-605-406447 target:[xpcservice<com.apple.appkit.xpc.ThemeWidgetControlViewService([app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853])(501)>{vt hash: 0}:97786:97786] explanation:"viewBridge:97786" active originator:[osservice<com.apple.coreservices.launchservicesd>:605] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom prevSus runningReason:20251 legRes:0 doms:com.apple.launchservicesd:RoleViewBridge invOnConds:(null)> processState:<RBProcessState| role:UserInteractiveNonFocal> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.launchservicesd" name:"RoleViewBridge" sourceEnvironment:"(null)">
	]>
	<RBAssertion| identifier:637-633-455233 target:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] explanation:"AppVisible" active originator:[osservice<com.apple.WindowServer(88)>:633] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom prevSus runningReason:20242 legRes:0 doms:com.apple.appnap:AppVisible invOnConds:(null)> processState:<RBProcessState| role:Background> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"AppVisible" sourceEnvironment:"(null)">,
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>
	]>
2026-10-20 13:32:37.835 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 6
	<RBAssertion| identifier:637-97786-406506 target:[xpcservice<com.apple.appkit.xpc.ThemeWidgetControlViewService([app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853])(501)>{vt hash: 0}:97786:97786] explanation:"AppNap adapter assertion" active originator:[xpcservice<com.apple.appkit.xpc.ThemeWidgetControlViewService([app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853])(501)>{vt hash: 0}:97786:97786] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom runningReason:0 legRes:0 doms:com.apple.appnap:Enable,com.apple.appnap:PreventTimerThrottleTier5 invOnConds:(null)> processState:<RBProcessState| role:None> suspended: attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier5" sourceEnvironment:"(null)">
	]>
	<RBAssertion| identifier:637-633-455107 target:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] explanation:"AppDrawing" active originator:[osservice<com.apple.WindowServer(88)>:633] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom runningReason:0 legRes:0 doms:com.apple.appnap:AppDrawing invOnConds:(null)> processState:<RBProcessState| role:None> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"AppDrawing" sourceEnvironment:"(null)">,
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>
	]>
2026-10-20 13:32:37.836 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 11
	<RBAssertion| identifier:637-633-455235 target:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] explanation:"FUSBProcessWindowState: visible" active originator:[osservice<com.apple.WindowServer(88)>:633] transientState:<RBAssertionTransientState| policies:[
	
	] tags:[
	SupportsBackgroundAudio> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dreldom prevSus runningReason:10000 legRes:0 doms:com.apple.fuseboard:Visible invOnConds:(null)> processState:<RBProcessState| role:UserInteractiveNonFocal> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.fuseboard" name:"Visible" sourceEnvironment:"(null)">,
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>
	]>
2026-10-20 13:32:37.837 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 14
	<RBAssertion| identifier:637-605-646 target:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] explanation:"foregroundApp:853" active originator:[osservice<com.apple.coreservices.launchservicesd>:605] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom prevSus runningReason:20248 legRes:0 doms:com.apple.launchservicesd:RoleUserInteractiveNonFocal invOnConds:(null)> processState:<RBProcessState| role:UserInteractiveNonFocal> suspended: attributes:[
	<RBSDomainAttribute| domain:"com.apple.launchservicesd" name:"RoleUserInteractiveNonFocal" sourceEnvironment:"(null)">
	]>
2026-10-20 13:32:37.839 Sd runningboardd[637:0] (46BC7329-2B6C-3985-A5EC-D24BB500A686) RBSStateCaptureSet Segment 24
	<RBAssertion| identifier:637-853-453725 target:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] explanation:"AppNap adapter assertion" active originator:[app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] transientState:<RBAssertionTransientState| policies:[
	
	]> intransientState:<RBAssertionIntransientState| strt:Unspecified end:WarnOnly nvld:0.00 warn:0.00dom prevSus runningReason:20243 legRes:0 doms:com.apple.appnap:Enable,com.apple.appnap:Inactive,com.apple.appnap:PreventDiskThrottle,com.apple.appnap:PreventSuppressedCPU,com.apple.appnap:PreventLowPriorirtyCPU,com.apple.appnap:PreventBackgroundSockets,com.apple.appnap:PreventTimerThrottleTier0 invOnConds:(null)> processState:<RBProcessState| role:Background> suspended: attributes:[
	<RBSAcquisitionCompletionAttribute| policy:AfterApplication>,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Enable" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"Inactive" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventDiskThrottle" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventSuppressedCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventLowPriorirtyCPU" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventBackgroundSockets" sourceEnvironment:"(null)">,
	<RBSDomainAttribute| domain:"com.apple.appnap" name:"PreventTimerThrottleTier0" sourceEnvironment:"(null)">
	]>
2026-10-20 13:43:38.961 Df runningboardd[637:dfabc0b] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:47:34.466 Df runningboardd[637:e00080b] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:47:35.797 Df runningboardd[637:dff8fe8] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:50:16.118 Df runningboardd[637:e03d31d] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:50:17.497 Df runningboardd[637:e03e0fc] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:50:31.732 Df runningboardd[637:e03e0fa] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:50:33.126 Df runningboardd[637:e03e0fa] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:52:26.254 Df runningboardd[637:e06f836] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:52:27.610 Df runningboardd[637:e06f83b] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:53:01.469 Df runningboardd[637:e06f836] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
2026-10-20 13:53:42.787 Df runningboardd[637:e07281c] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveFocal
2026-10-20 13:53:51.770 Df runningboardd[637:e081b5f] [com.apple.runningboard:ttl] [app<application.net.kovidgoyal.kitty.330945848.330945854(501)>:853] Set darwin role to: UserInteractiveNonFocal
FX
}

# ── status ────────────────────────────────────────────────────────────────────────────────────────
@test "T4 green: key on and written before kitty started → adopted=yes, verdict=OK, exit 0" {
  st
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(line key)" = key=on ]
  [[ "$(line adopted)" == "adopted=yes "* ]] || { echo "$output"; false; }
  [ "$(line band)" = band=31/47T ]
  [ "$(line fds)" = "fds=40/256 fds_all=90 fds_unix=2" ]
  [ "$(line main_kitties)" = main_kitties=1 ]
  [[ "$(line version)" == "version=0.49.2 team=NTY7FVCEKP signature=developer fixes=signal:y listener:n" ]] || { echo "$output"; false; }
  [ "$(line load1)" = "load1=150.00 ncpu=10" ]
  [ "$(printf '%s\n' "$output" | tail -1)" = verdict=OK ]
}

@test "T1 the defaults stub says 'does not exist' → key=absent, WARN(key), exit 1" {
  echo absent > "$T/bin/defaults.mode"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(line key)" = key=absent ]
  [[ "$(printf '%s\n' "$output" | tail -1)" == "verdict=WARN(key"* ]] || { echo "$output"; false; }
  [[ "$(line adopted)" == "adopted=n/a"* ]] || false
}

@test "T2 a cfprefsd error is key=? and WARN(unknown:key) — never absent, never on, never OK" {
  echo err > "$T/bin/defaults.mode"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(line key)" = 'key=?' ]
  [[ "$output" == *"verdict=WARN(unknown:key"* ]] || { echo "$output"; false; }
  [[ "$(line adopted)" == 'adopted=?'* ]] || false
}

@test "T3 key on but written AFTER kitty started → adopted=pending, WARN" {
  echo "$((START + 100))" > "$T/mtime/net.kovidgoyal.kitty.plist"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$(line adopted)" == "adopted=pending "* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=WARN(adopted)"* ]] || { echo "$output"; false; }
}

@test "S11 ps runs under TZ=UTC LC_ALL=C: the operator-locale lstart cannot reach the date parse" {
  st
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^TZ=UTC LC_ALL=C -p '"$KP"' -o lstart=$' "$T/bin/ps.log" || { cat "$T/bin/ps.log"; false; }
  grep -q '^TZ=UTC LC_ALL=C -axo pid=,ppid=,lstart=,args=$' "$T/bin/ps.log"
}

@test "S11 an unreadable start is adopted=? WARN(unknown:adopted), never yes" {
  : > "$T/bin/ps.starts"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$(line adopted)" == 'adopted=? '* ]] || { echo "$output"; false; }
  [[ "$output" == *"unknown:adopted"* ]] || false
}

@test "T5 band 4 is WARN(napped-now); an unreadable band is band=? WARN(unknown:band)" {
  echo 4 > "$T/band.val"; echo 4T > "$T/bin/ps.thr"
  st
  [ "$status" -eq 1 ] && [ "$(line band)" = band=4/4T ] || { echo "$output"; false; }
  [[ "$output" == *"WARN(napped-now)"* ]] || { echo "$output"; false; }
  echo '?' > "$T/band.val"
  st
  [ "$status" -eq 1 ] && [[ "$(line band)" == 'band=?/'* ]] || { echo "$output"; false; }
  [[ "$output" == *"unknown:band"* ]] || false
}

@test "T6 190 numeric fds is WARN(fds); every-row count over CC_RESTORE_FD_MAX is WARN(restore-fd-gate); unix sockets counted" {
  echo 190 > "$T/bin/lsof.n"; echo 7 > "$T/bin/lsof.unix"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(line fds)" = "fds=190/256 fds_all=240 fds_unix=7" ] || { echo "$output"; false; }
  [[ "$output" == *"WARN(fds,restore-fd-gate)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"a second cc-restore round would STOP"* ]] || false
}

@test "T6b an lsof that outlives CC_KH_LSOF_TIMEOUT_S is fds=? WARN(unknown:fds), within the bound" {
  echo 30 > "$T/bin/lsof.sleep"; export CC_KH_LSOF_TIMEOUT_S=1
  s=$SECONDS; st; el=$((SECONDS - s))
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(line fds)" = "fds=?/256 fds_all=? fds_unix=?" ] || { echo "$output"; false; }
  [[ "$output" == *"unknown:fds"* ]] || false
  [ "$el" -lt 15 ] || { echo "took ${el}s — the bound did not fire"; false; }
}

@test "T7 a dev kitty makes main_kitties=2 WARN and names its parent; a b8 probe is listed and WARNs; a +kitten helper is ignored" {
  sleep 600 & BG=$!
  census "$KP 1 $START $T/kitty.app/Contents/MacOS/kitty" \
         "41398 1 $START /bin/zsh -l" \
         "41475 41398 $START /Users/x/kitty-pr3/kitty/launcher/kitty --config=NONE" \
         "$BG 1 $START $T/kitty.app/Contents/MacOS/kitty --config NONE --instance-group b8-ctl --listen-on unix:/tmp/b8probe/ctl.sock" \
         "5151 $KP $START $T/kitty.app/Contents/MacOS/kitty +kitten ask"
  st --pid "$KP"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$(line main_kitties)" == "main_kitties=2 (cc-restore --restart-kitty will refuse"* ]] || { echo "$output"; false; }
  [[ "$output" == *"main=41475 ppid=41398 parent=/bin/zsh "* ]] || { echo "$output"; false; }
  [[ "$output" == *"probe=$BG group=b8-ctl ppid=1 (cc-restore's open -a would activate this probe"* ]] || { echo "$output"; false; }
  [[ "$output" != *"main=5151"* ]] || false
  [[ "$output" == *"WARN(main,probe)"* ]] || { echo "$output"; false; }
}

@test "E-12 not exactly one main kitty and no --pid: per-pid checks are n/a, never a --pid 0 read" {
  census "$KP 1 $START $T/kitty.app/Contents/MacOS/kitty" "41475 41398 $START /Users/x/kitty-pr3/kitty/launcher/kitty"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"per-pid checks: n/a (no single main kitty; pass --pid)"* ]] || { echo "$output"; false; }
  ! grep -q -- '-p 0 ' "$T/bin/ps.log" || false
  [[ "$output" != *"band="* ]] || false
}

@test "T8 zombies on 0.48.2 WARN(signals, kitty#10436); the same count on 0.49.2 does not" {
  printf '%s Z\n%s Z\n%s S\n' "$KP" "$KP" "$KP" > "$T/bin/ps.zombies"
  echo 0.48.2 > "$T/bin/PlistBuddy.ver"
  st
  [ "$status" -eq 1 ] && [ "$(line zombies)" = zombies=2 ] || { echo "$output"; false; }
  [[ "$output" == *"WARN(signals)"* ]] || { echo "$output"; false; }
  [[ "$(line version)" == *"fixes=signal:n listener:n" ]] || false
  echo 0.49.2 > "$T/bin/PlistBuddy.ver"
  st
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "S12d a bundle newer than the running process is version=? WARN, and cannot suppress the zombie WARN" {
  printf '%s Z\n' "$KP" > "$T/bin/ps.zombies"
  echo "$((START + 60))" > "$T/mtime/kitty"
  st
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$(line version)" == "version=? (bundle 0.49.2; kitty $KP runs "* ]] || { echo "$output"; false; }
  [[ "$output" == *"WARN(version,signals)"* ]] || { echo "$output"; false; }
}

@test "an adhoc signature WARNs" {
  : > "$T/bin/codesign.adhoc"
  st
  [ "$status" -eq 1 ] && [[ "$output" == *"signature=adhoc"* ]] && [[ "$output" == *"WARN(adhoc)"* ]] || { echo "$output"; false; }
}

@test "--only key,main,probe is the cheap form: one defaults read and one ps, nothing per-pid" {
  echo absent > "$T/bin/defaults.mode"
  st --only key,main,probe --pid "$KP"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | head -1)" = key=absent ]
  [ "$(grep -c . "$T/bin/defaults.log")" -eq 1 ]
  [ "$(grep -c . "$T/bin/ps.log")" -eq 1 ]
  [ ! -e "$T/bin/kitten.log" ]
  [[ "$output" != *"band="* ]] && [[ "$output" != *"fds="* ]] || false
  [ "$(printf '%s\n' "$output" | tail -1)" = "verdict=WARN(key)" ]
}

@test "a census ps that fails is main_kitties=? WARN(unknown:main), never 'no kitty'" {
  echo 1 > "$T/bin/ps.rc"
  st --only key,main,probe
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"main_kitties=? (ps rc 1)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"unknown:main"* ]] || false
}

@test "usage: an unknown --only field and an unknown verb exit 2" {
  st --only key,bogus
  [ "$status" -eq 2 ]
  run /bin/bash "$SUT" restart
  [ "$status" -eq 2 ]
}

@test "kill switch: CC_KITTY_HYGIENE=off prints verdict=OFF, exit 0, and reads nothing" {
  CC_KITTY_HYGIENE=off st
  [ "$status" -eq 0 ] && [ "$output" = "verdict=OFF (CC_KITTY_HYGIENE=off)" ] || { echo "$output"; false; }
  [ ! -e "$T/bin/defaults.log" ] && [ ! -e "$T/bin/ps.log" ]
}

@test "the timeout resolver passes -k when a timeout(1) exists" {
  printf '#!/bin/bash\necho "$*" >> "$0.log"\nshift 3\nexec "$@"\n' > "$T/bin/fake-timeout"; chmod +x "$T/bin/fake-timeout"
  CC_KH_TIMEOUT_BIN="$T/bin/fake-timeout" st --only key
  grep -q '^-k 2 60 ' "$T/bin/fake-timeout.log" || { cat "$T/bin/fake-timeout.log"; false; }
}

# ── T9: read-only, by behaviour and by source ─────────────────────────────────────────────────────
@test "T9 every verb, with argv-logging stubs: no defaults write/delete, no kill/open/brew/launchctl/osascript" {
  st
  run /bin/bash "$SUT" naps --pid "$KP"
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 2 --out "$T/s.tsv"
  [ ! -e "$T/forbidden.log" ] || { cat "$T/forbidden.log"; false; }
  ! grep -v '^read net.kovidgoyal.kitty NSAppSleepDisabled$' "$T/bin/defaults.log" || false
}

# The source lint: comments and the one delimited own-child bound block are stripped; what is left
# may name no signal sender but `kill -0`, no setting writer, no launcher, and no RC verb but `ls`.
lint() {
  awk '/^# BEGIN own-child bound/ { skip = 1 } /^# END own-child bound/ { skip = 0; next } skip { next }
       { line = $0; sub(/^[[:space:]]*#.*/, "", line); if (line != "") print FNR ": " line }' "$1" \
    | grep -E '(^|[^[:alnum:]_.-])(kill|pkill|killall|launchctl|osascript|brew|taskpolicy|renice)([^[:alnum:]_-]|$)|[Dd][Ee][Ff][Aa][Uu][Ll][Tt][Ss]"?[[:space:]]+(write|delete)|(^[0-9]+: +|[;&|(] *|(then|do|else) +)("?/usr/bin/)?open"?[[:space:]]+-|KITTEN"?[[:space:]]+@' \
    | grep -v -E '(^|[^[:alnum:]_])kill -0 |KITTEN"?[[:space:]]+@[[:space:]]+--to[[:space:]]+"\$sock"[[:space:]]+ls '
}

@test "T9 lint: kitty-hygiene.sh sends no signal but kill -0 and writes no setting" {
  run lint "$SUT"
  [ -z "$output" ] || { echo "offending lines: $output"; false; }
}

@test "T9 lint mutants die: an added kill -TERM, a defaults write, an open -a, a launchctl, an RC close-window" {
  local m
  for m in 'kill -TERM "$pid"' '"$DEFAULTS" write "$DOMAIN" NSAppSleepDisabled -bool YES' \
           '/usr/bin/defaults delete net.kovidgoyal.kitty' '/usr/bin/open -a /Applications/kitty.app' \
           'launchctl kickstart gui/501/x' '"$KITTEN" @ --to "$sock" close-window'; do
    { cat "$SUT"; printf '%s\n' "$m"; } > "$T/mut.sh"
    run lint "$T/mut.sh"
    [ -n "$output" ] || { echo "mutant survived the lint: $m"; false; }
  done
}

# ── naps ──────────────────────────────────────────────────────────────────────────────────────────
naps() { run /bin/bash "$SUT" naps --pid "$KP" "$@"; }

@test "T10 the 10-19 incident capture is NAPPING with the 713 s focal nap, exit 1" {
  fx_incident | sed "s/:853\]/:$KP]/g" > "$T/bin/log.slice"
  naps
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"naps: interval 2026-10-19 22:56:48 -> 2026-10-19 23:08:41 713s nonfocal=0s roles=UserInteractiveFocal"* ]] || { echo "$output"; false; }
  [[ "$output" == *"napped_focal=713s"* ]] || false
  [ "$(printf '%s\n' "$output" | tail -1)" = naps=NAPPING ]
}

@test "T10b a keyed app's capture (Dia 1037): a challenge and a dump with no adapter → NO-ADAPTER, exit 0" {
  fx_dia | sed "s/:1037\]/:$KP]/g" > "$T/bin/log.slice"
  naps
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -1)" = naps=NO-ADAPTER ]
}

@test "T10c an empty capture is UNKNOWN (exit 3), never NO-ADAPTER; so is a slice our bound cut" {
  naps
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"naps=UNKNOWN (no state dump lists the pid's assertions; no challenge"* ]] || { echo "$output"; false; }
  fx_dia | sed "s/:1037\]/:$KP]/g" > "$T/bin/log.slice"; rm -f "$T/bin/log.n"; echo 124 > "$T/bin/log.slice-rc"
  naps
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"naps=UNKNOWN (1 of 1 slice(s) uncovered)"* ]] || { echo "$output"; false; }
}

@test "T10c a log show that hangs past --timeout is bounded per slice: UNKNOWN, within the bound" {
  : > "$T/bin/log.hang"
  s=$SECONDS; naps --timeout 1; el=$((SECONDS - s))
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"rc=124 UNCOVERED"* ]] || { echo "$output"; false; }
  [ "$el" -lt 15 ] || { echo "took ${el}s — the slice bound did not fire"; false; }
}

@test "T10d retention rolled past --since (no unfiltered line) is UNKNOWN even over a clean capture" {
  fx_dia | sed "s/:1037\]/:$KP]/g" > "$T/bin/log.slice"; : > "$T/bin/log.retention"
  naps
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"retention rolled"* ]] || { echo "$output"; false; }
}

@test "T10e adapters carrying the full Prevent set only → ENROLLED, exit 1" {
  fx_incident | head -10 | sed "s/:853\]/:$KP]/g" > "$T/bin/log.slice"
  naps
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | tail -1)" == "naps=ENROLLED"* ]] || { echo "$output"; false; }
}

@test "T10f kitty 853's 30-minute capture (role lines + an adapter HELD in a state dump) → ENROLLED, never NO-ADAPTER" {
  fx_enrolled | sed "s/:853\]/:$KP]/g" > "$T/bin/log.slice"
  naps
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"acquisitions=0 held_adapters=1 dumps=1"* ]] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | tail -1)" == "naps=ENROLLED"* ]] || { echo "$output"; false; }
}

@test "T10f the hosted xpcservice in the same dump is not the kitty: parser direct on the real lines" {
  fx_enrolled > "$T/e.txt"
  run /usr/bin/python3 -I "$NAPS" parse "$T/e.txt" --pid 853 --json
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  /usr/bin/python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["held_adapters"]==1 and d["verdict"]=="ENROLLED", d' "$output"
}

@test "a partial capture with a napped adapter is still NAPPING (positive evidence), though the slice is uncovered" {
  fx_incident | sed "s/:853\]/:$KP]/g" > "$T/bin/log.slice"; echo 124 > "$T/bin/log.slice-rc"
  naps
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"covered=0"* ]] && [ "$(printf '%s\n' "$output" | tail -1)" = naps=NAPPING ] || { echo "$output"; false; }
}

@test "--since defaults to the process start; an earlier --since is refused (a reused pid)" {
  naps
  want="$(/bin/date -r "$START" '+%Y-%m-%d %H:%M:%S')"
  grep -q -- "--start $want " "$T/bin/log.log" || { cat "$T/bin/log.log"; false; }
  naps --since "$(/bin/date -r "$((START - 60))" '+%Y-%m-%d %H:%M:%S')"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"refused — a reused pid would count another process's lines"* ]] || { echo "$output"; false; }
}

@test "a 2 h window is sliced into 20-minute slices, each its own query; --max-slices leaves the rest uncovered" {
  census "$KP 1 $((NOW - 7200)) $T/kitty.app/Contents/MacOS/kitty"
  naps
  [ "$(grep -c 'eventMessage CONTAINS' "$T/bin/log.log")" -ge 6 ] || { cat "$T/bin/log.log"; false; }
  [ "$(grep -c 'eventMessage CONTAINS' "$T/bin/log.log")" -le 7 ] || false
  rm -f "$T/bin/log.log" "$T/bin/log.n"
  naps --max-slices 2
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(grep -c 'eventMessage CONTAINS' "$T/bin/log.log")" -eq 2 ]
  [[ "$output" == *"uncovered (past --max-slices 2)"* ]] || { echo "$output"; false; }
}

@test "naps is never run inside cc-restore" {
  CC_KH_CALLER=cc-restore naps
  [ "$status" -eq 2 ] && [[ "$output" == *"never run inside cc-restore"* ]] || { echo "$output"; false; }
  [ ! -e "$T/bin/log.log" ]
}

# ── sample ────────────────────────────────────────────────────────────────────────────────────────
@test "sample: no RC call to a main kitty by default; each row carries load1 and the band" {
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 2 --out "$T/s.tsv"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$T/bin/kitten.log" ]
  [ "$(head -1 "$T/s.tsv")" = "$(printf 'ts\tpid\tload1\tlocked\tfront\tband\tmain_thr\tthreads_at_4\trc_rc\trtt_ms\tfds\tfds_unix')" ]
  [ "$(awk -F'\t' 'NR > 1 { print $3, $6, $7, $9, $11, $12 }' "$T/s.tsv" | sort -u)" = "150.00 31 47T - 40 2" ] || { cat "$T/s.tsv"; false; }
}

@test "sample: --rc to a main kitty needs --rc-production" {
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 1 --rc unix:/tmp/b8probe/x.sock --out "$T/s.tsv"
  [ "$status" -eq 2 ] && [[ "$output" == *"needs --rc-production"* ]] || { echo "$output"; false; }
  [ ! -e "$T/bin/kitten.log" ]
}

@test "S2 sample: after the first unanswered call it stops calling while the band reads below 31" {
  echo 1 > "$T/bin/kitten.rc"; echo 4 > "$T/band.val"
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 4 --rc unix:/tmp/b8probe/x.sock --rc-production --out "$T/s.tsv"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$T/bin/kitten.log")" -eq 1 ] || { cat "$T/bin/kitten.log"; false; }
  [ "$(awk -F'\t' 'NR > 1 { print $9 }' "$T/s.tsv" | tr '\n' ' ')" = "1 - - - " ] || { cat "$T/s.tsv"; false; }
}

@test "S2 sample: at most 10 unanswered calls per run, whatever the band says" {
  echo 1 > "$T/bin/kitten.rc"
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 14 --rc unix:/tmp/b8probe/x.sock --rc-production --out "$T/s.tsv"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$T/bin/kitten.log")" -eq 10 ] || { cat "$T/bin/kitten.log"; false; }
  [[ "$output" == *"unanswered rc calls: 10/10"* ]] || false
}

@test "sample: answered calls keep going and record rc 0" {
  run /bin/bash "$SUT" sample --pid "$KP" --every 0 --count 3 --rc unix:/tmp/b8probe/x.sock --rc-production --out "$T/s.tsv"
  [ "$(grep -c . "$T/bin/kitten.log")" -eq 3 ]
  grep -qx -- '@ --to unix:/tmp/b8probe/x.sock ls' "$T/bin/kitten.log"
  [ "$(awk -F'\t' 'NR > 1 { print $9 }' "$T/s.tsv" | tr '\n' ' ')" = "0 0 0 " ] || { cat "$T/s.tsv"; false; }
}

# ── the fd-headroom kitten (O2b) — no live kitty: the script form reads its own process ───────────
@test "headroom get reads a fixture limit back and changes nothing" {
  run /bin/bash -c "ulimit -Sn 300; /usr/bin/python3 -I '$FDH' get; /usr/bin/python3 -I '$FDH' get"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed 's/pid=[0-9]* //' | sort -u)" = "fd_headroom=get soft=300 hard=unlimited" ] || { echo "$output"; false; }
}

@test "headroom set raises the soft limit to 8192, or to a lower hard limit, and never touches the hard one" {
  run /bin/bash -c "ulimit -Sn 256; /usr/bin/python3 -I '$FDH' set"
  [ "$status" -eq 0 ] && [[ "$output" == *"soft=256->8192 hard=unlimited"* ]] || { echo "$output"; false; }
  run /bin/bash -c "ulimit -Sn 300; ulimit -Hn 1000; /usr/bin/python3 -I '$FDH' set"
  [ "$status" -eq 0 ] && [[ "$output" == *"soft=300->1000 hard=1000"* ]] || { echo "$output"; false; }
}

@test "headroom: kitty's handle_result entry point returns the line (never raises); a bad mode is an error line" {
  run /usr/bin/python3 -I -c 'import importlib.util as u, sys
s = u.spec_from_file_location("k", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
print(m.handle_result(["kitty-fd-headroom.py", "get"], None, 0, None)); print(m.handle_result(["k", "bogus"], None, 0, None))' "$FDH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | head -1)" == "fd_headroom=get pid="* ]] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | tail -1)" == "fd_headroom=error unknown mode 'bogus'"* ]] || { echo "$output"; false; }
}

@test "headroom source: no signal, no subprocess, no settings write — it runs inside kitty" {
  run grep -n -E '^(import|from) (signal|subprocess)|os\.(kill|killpg|system|popen)|defaults write' "$FDH"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}
