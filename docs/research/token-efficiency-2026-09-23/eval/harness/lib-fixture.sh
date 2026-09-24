# lib-fixture.sh — sourced by task fixture.sh files. Deterministic git identity and dates.
fx_init() {  # fx_init <dir> [origin-bare-dir]
  FX=${1:?fixture dir required}; R=${2:-}
  rm -rf "$FX"; [ -n "$R" ] && rm -rf "$R"
  mkdir -p "$FX"; git init -q -b main "$FX"
  git -C "${FX:?fixture dir required}" config user.name "Chris Ren"
  git -C "${FX:?fixture dir required}" config user.email "dev@example.invalid"
  export GIT_AUTHOR_DATE="2026-09-10T12:00:00Z" GIT_COMMITTER_DATE="2026-09-10T12:00:00Z"
}
fx_commit() {  # fx_commit <message> [date]  (stages everything, then commits)
  [ -n "${2:-}" ] && export GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2"
  git -C "${FX:?}" add -A && git -C "${FX:?}" commit -q -m "$1"
}
fx_origin() {  # create the bare origin and push main
  git init -q --bare "${R:?origin dir required}"
  git -C "${FX:?}" remote add origin "$R"
  git -C "${FX:?}" push -q -u origin main
}
