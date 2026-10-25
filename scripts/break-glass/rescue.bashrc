# shellcheck shell=bash
# rescue.bashrc — the rc file of the iTerm2 "Rescue" profile:
#   /bin/bash --noprofile --rcfile ~/.claude/scripts/break-glass/rescue.bashrc -i
# A shell for when no terminal can start one (incident 2026-10-25): one poisoned devfs node made every
# zsh and /usr/bin/login hang in ttyname() → devname() → lstat (rca/diag-reports.md §2a). Interactive
# bash 3.2 calls ttyname only for the `\l` prompt escape and a /dev/tty fallback, so it still starts.
# This file keeps it that way: no `\l`, no pager, and the commands that walk /dev are shadowed with a
# warning that names the safe form. `command <name>` still reaches the real binary on purpose.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.claude/bin
export PAGER=cat MANPAGER=cat GIT_PAGER=cat LESS='' BASH_SILENCE_DEPRECATION_WARNING=1
export RESCUE_SH="$HOME/.claude/scripts/break-glass/rescue.sh"
PS1='[RESCUE \u@\h \W]\$ '      # never \l: it is the one bash prompt escape that calls ttyname()
PROMPT_COMMAND=
unset MAILCHECK

mkdir -p "$HOME/.claude/autonomy/break-glass" &&
  date +%s > "$HOME/.claude/autonomy/break-glass/rescue-profile.last"

_rescue_refuse() { # <what> <why> <instead>
  printf 'rescue: refusing %s — %s.\n  instead: %s\n  (the real binary: command %s …)\n' "$1" "$2" "$3" "${1%% *}" >&2
  return 2
}

zsh()    { _rescue_refuse zsh "it calls ttyname() at startup and hangs on a poisoned /dev" "stay in this bash"; }
login()  { _rescue_refuse login "it hangs in ttyname() (17 login sleepers on 2026-10-25)" "stay in this bash"; }
su()     { _rescue_refuse su "it resolves the tty name through /dev" "osascript -e 'do shell script \"…\" with administrator privileges'"; }
sudo()   { _rescue_refuse sudo "it resolves the tty name through devname()" "osascript -e 'do shell script \"…\" with administrator privileges'"; }
tty()    { _rescue_refuse tty "it calls ttyname()" "ps -o tdev= -p \$\$   (16/N is ttys%03d)"; }
who()    { _rescue_refuse who "it walks /dev for every login line" "psx"; }
w()      { _rescue_refuse w "it walks /dev for every login line" "psx"; }
less()   { _rescue_refuse less "a pager opens /dev/tty" "cat, head or tail"; }
more()   { _rescue_refuse more "a pager opens /dev/tty" "cat, head or tail"; }
man()    { _rescue_refuse man "it runs a pager on /dev/tty" "MANPAGER=cat command man … | head -100"; }
screen() { _rescue_refuse screen "it allocates and names ptys" "a second Rescue window"; }
tmux()   { _rescue_refuse tmux "it allocates and names ptys" "a second Rescue window"; }
lsof()   { _rescue_refuse lsof "it lstat-scans /dev for device names" "psx; or kit (rescue.sh capture)"; }

# ps is safe only with -x and without a tty column (adv_cmds ps.c:681-690, print.c:619-649)
ps() {
  local a all=" $* " x=0 o=0 bad=0
  for a in "$@"; do
    case "$a" in
      -*[!A-Za-z]*) ;;                                   # not a flag cluster (a value like -1)
      -*) case "$a" in *[xAe]*) x=1 ;; esac
          case "$a" in *[MtTjlf]*) bad=1 ;; esac
          case "$a" in *[oO]*) o=1 ;; esac ;;
      *) case ",$a," in *,tt,*|*,tty,*|*,tt=*|*,tty=*) bad=1 ;; esac ;;
    esac
  done
  if [ "$x$o$bad" = 110 ]; then command ps "$@"; return; fi
  _rescue_refuse "ps$all" "without -x, with a tty column, -t/-T/-M or the default format it calls devname()" \
    "psx   (= ps -axww -o pid,ppid,pgid,stat,etime,%cpu,tdev,ucomm)"
}
psx() { command ps -axww -o pid,ppid,pgid,stat,etime,%cpu,tdev,ucomm "$@"; }

# `-f claude` matches lockwatch, the sentinel and every script that mentions claude in its argv;
# `taskpolicy -b` demotes to the background band, where a capture once came back empty.
_rescue_claude_pattern() { local a; for a in "$@"; do case "$a" in -f*|-*f) _rf=1 ;; *claude*) _rc=1 ;; esac; done; }
pgrep() {
  local _rf=0 _rc=0; _rescue_claude_pattern "$@"
  if [ "$_rf$_rc" = 11 ]; then
    _rescue_refuse "pgrep $*" "-f claude also matches lockwatch and the sentinel" "command pgrep -a -x 'claude(\\.exe)?'"; return
  fi
  command pgrep "$@"   # devname-hazard-lint:allow the operator's own flags, passed through
}
pkill() {
  local _rf=0 _rc=0; _rescue_claude_pattern "$@"
  if [ "$_rf$_rc" = 11 ]; then
    _rescue_refuse "pkill $*" "-f claude also matches lockwatch and the sentinel" \
      "command pkill -STOP -x 'claude(\\.exe)?'  — or hold new spawns: brownout"; return
  fi
  command pkill "$@"
}
taskpolicy() {
  case " $* " in *' -b '*) _rescue_refuse "taskpolicy $*" "the background band starves the process you are rescuing" "brownout"; return ;; esac
  command taskpolicy "$@"
}

kit()      { /bin/bash "$RESCUE_SH" capture; }
unpoison() { /bin/bash "$RESCUE_SH" unpoison "$@"; }
brownout() { /bin/bash "$RESCUE_SH" brownout "$@"; }
lwstate()  { cat "$HOME/.claude/autonomy/lockwatch/state.json"; echo; }

cat <<'EOF'
RESCUE shell (bash, no login, no zsh). Safe tools:
  kit                      capture kit → ~/.claude/autonomy/break-glass/kits/ (prints a summary)
  lwstate                  lockwatch's current verdict (diagnosis names pgid + leader lstart)
  unpoison <pgid> <lstart> the cure for a poisoned /dev node: kill -KILL -- -<pgid>, re-verified
  brownout [min|off]       hold new fleet spawns (default 60 min)
  psx                      the process list, -axww, no tty column
Never: kill a pty session leader by pid, or kill kitty under a devfs verdict (Unpoison first).
Last resort: Apple menu > Restart (writes the shutdown_stall stackshot), never the power button.
EOF
