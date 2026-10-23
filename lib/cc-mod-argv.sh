# shellcheck shell=bash
# cc-mod-argv.sh — the ONE place that composes the `--plugin-dir` arguments a Claude Code session
# needs to load the live mods (accounts-readout: the /accounts board in the plugin panel).
#
# Sourced, never executed, by every path that starts an interactive session: lib/claude-launcher.zsh
# (the `claude`/`claudeN` functions), bin/reso-resume-one and scripts/limit-recover/lr-fire-resume.sh
# (the expect resume wrappers). It used to live only in the launcher, so every resume those two
# wrappers started came up WITHOUT the mod: 9 of 19 live 2.1.293 sessions on 2026-10-23, all of them
# expect-wrapper resumes (docs/research/startup-readout-visibility-2026-10-23.md, Symptom 1).
#
# Written for bash 3.2 AND zsh: lr-fire-resume.sh runs under /bin/bash, the launcher under zsh.
#
# cc_mod_argv — prints the argv, ONE TOKEN PER LINE (`--plugin-dir`, then the dir), for each
# ~/.claude/mods/<name>/ holding a .claude-plugin/plugin.json. install.sh links each mod as a
# DIRECTORY symlink, and the trailing-slash glob follows it. Prints nothing under CC_MODS=off or on a
# machine with no mods; always exits 0. One token per line rather than one pair per line so a caller
# can split on newlines alone (a mod path with a space stays one argument) and never re-pair them.
# A flag, never CLAUDE_CODE_PLUGIN_DIRS: an exported variable reaches every `claude -p` a session's
# shell runs, and a loaded mod costs ~50-60 MB RSS in a session that can draw nothing.
#
# cc_tui_env — prints `CLAUDE_CODE_NO_FLICKER=<v>` for a spawn's env prefix. Interactive shells get
# the variable from ~/.zshrc (`export CLAUDE_CODE_NO_FLICKER=1`), so a launcher session always has
# it; an expect wrapper started outside that rc did not, and one resumed session on 2026-10-23 came up
# on the classic renderer for that reason. A caller's own value is kept.

cc_mod_argv() {
  [ -n "${ZSH_VERSION:-}" ] && emulate -L sh    # sh globbing: an unmatched pattern stays literal
  [ "${CC_MODS:-on}" = off ] && return 0
  local d
  for d in "${HOME:-}"/.claude/mods/*/; do
    [ -f "${d}.claude-plugin/plugin.json" ] && printf -- '--plugin-dir\n%s\n' "${d%/}"
  done
  return 0
}

cc_tui_env() {
  printf 'CLAUDE_CODE_NO_FLICKER=%s\n' "${CLAUDE_CODE_NO_FLICKER:-1}"
}
