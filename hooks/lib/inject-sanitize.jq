# inject-sanitize.jq — `def inj_san`: make a stored string safe to place in a hook's
# additionalContext (truememory-2026-09-27.md §3.7, acceptance criterion of #6).
#
# TrueMemory's sanitizer escaped only `<truememory-*` and `<system`, and measured letting through a
# forged `\n## User Directives` section, `<function_calls>`, `<invoke>`, a full-width
# `＜system-reminder＞`, zero-width-split tags and ANSI residue. This one, in order:
#   1. strips CSI / OSC escape sequences whole (stripping ESC alone leaves `[31m` residue);
#   2. strips the remaining control characters (tab becomes a space);
#   3. strips zero-width and bidi characters, so a split tag re-joins BEFORE step 5 looks at it;
#   4. neutralises a leading `#`, `>` or `---` on every line (a heading or quote can only form at a
#      line start, and step 6 is about to remove the line starts);
#   5. escapes `<` / `＜` before the listed tag names case-insensitively, and — as a superset — before
#      ANY `/` or letter, since a pointer never needs a live tag;
#   6. flattens newlines to ` ⏎ `;
#   7. truncates to 200 characters AFTER escaping, so an escape can never be what gets cut back off.
#
# Linked nowhere live (install.sh links *.sh and *.py only): callers resolve it through their
# dereferenced self-path and pass that dir to `jq -L`, then `include "inject-sanitize";`.
def inj_san:
  tostring
  | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "")
  | gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)?"; "")
  | gsub("\u001b[@-_]?"; "")
  | gsub("\t"; " ")
  | gsub("\r"; "")
  | gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f]"; "")
  | gsub("[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]"; "")
  | gsub("(?<pre>^|\n)[ ]*(?<m>#|>|---)"; "\(.pre)\\\(.m)")
  | gsub("(<|＜)(?=\\s*/?\\s*(system|[a-z-]*reminder|function_calls|invoke|antml|untrusted_|important|teammate-message|task-notification|pasted_content|recalled|lesson))"; "&lt;"; "i")
  | gsub("(<|＜)(?=[/a-z!?])"; "&lt;"; "i")
  | gsub("\n"; " ⏎ ")
  | .[0:200];
