# a2-memmirror-scan.zsh (zsh, run as `zsh -f <file>`; no shebang, like lib/*.zsh, so the bash gate skips it) — READ-ONLY replay of the scan half of lib/config-mirror.zsh
# _cc_sync_memory_mirror (lines 299-307) for one account: build the slug union of
# ~/.claude/projects/*(N/) and <dst>/projects/*(N/), then zstat -L each <dst>/projects/<slug>/memory
# link and compare it with the canonical target. It never creates, moves or links anything: the
# branches that would mutate are only COUNTED. Prints wall ms per phase.
# Usage: zsh -f a2-memmirror-scan.zsh ~/.claude-quaternary
zmodload zsh/stat 2>/dev/null
zmodload zsh/datetime
dst="${1:?usage: a2-memmirror-scan.zsh <account dir>}"
cano="$HOME/.claude/projects"
typeset -A slugs
t0=$EPOCHREALTIME
for sp in "$cano"/*(N/); do slugs[${sp:t}]=1; done
t1=$EPOCHREALTIME
for sp in "$dst/projects"/*(N/); do slugs[${sp:t}]=1; done
t2=$EPOCHREALTIME
ok=0 would_link=0 would_skip=0 other=0
for slug in ${(k)slugs}; do
  c="$cano/$slug/memory"; d="$dst/projects/$slug/memory"
  if [[ -L "$d" ]]; then
    typeset -a _z; _z=()
    zstat -L -A _z +link -- "$d" 2>/dev/null
    [[ "${_z[1]}" == "$c" ]] && { ok=$((ok+1)); continue; }
  fi
  if [[ -d "$d" && ! -L "$d" ]]; then would_skip=$((would_skip+1))
  elif [[ -d "$c" ]]; then would_link=$((would_link+1))
  else other=$((other+1)); fi
done
t3=$EPOCHREALTIME
printf 'account=%s slugs=%d  glob(cano)=%.0fms glob(dst)=%.0fms link-check=%.0fms total=%.0fms\n' \
  "${dst:t}" ${#slugs} $(( (t1-t0)*1000 )) $(( (t2-t1)*1000 )) $(( (t3-t2)*1000 )) $(( (t3-t0)*1000 ))
printf '  already-linked=%d  would-mkdir+ln(fork x2 each)=%d  real-dir-skip=%d  no-canonical-memory=%d\n' \
  $ok $would_link $would_skip $other
printf '  load: %s\n' "$(sysctl -n vm.loadavg)"
