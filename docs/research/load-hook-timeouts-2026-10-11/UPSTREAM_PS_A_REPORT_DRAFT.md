# DRAFT — upstream bug report for anthropics/claude-code (not posted; needs the operator's OK)

Status: draft written 2026-10-17 for load plan O4 (backlog `c2aa7ab8be97`). Post only after the
operator approves the text. Re-check against the current Claude Code release first: the evidence
below is from 2.1.293.

---

**Title:** killProcessTree spawns `ps -A` with no timeout and never kills it; children pile up under load (macOS)

**Version:** 2.1.293 (darwin-arm64 native build). Not yet re-checked on the latest release.

**What happens.** When the system is heavily loaded, `ps -A` on macOS can block for minutes.
The process-tree helper used by killProcessTree spawns `ps -A -o pid= -o ppid=` with no timeout,
and its promise resolves only on the child's `close` event. Nothing ever kills the child. Every
tree walk that runs while `ps` is slow leaves another `ps` behind, so they accumulate under the
`claude` process and add load at the moment the machine can least afford it.

**Evidence.**
- One `claude` process had 14 live `ps -A -o pid= -o ppid=` children at the same time (process-tree
  capture taken while the session was shutting down).
- On the same machine we have seen 224 orphaned `ps` processes reparented to launchd.
- The helper as it appears in the 2.1.293 binary (minified):

  ```js
  e=P("ps",["-A","-o","pid=","-o","ppid=",...l],{cwd:"/",stdio:["ignore","pipe","ignore"],windowsHide:!0})
  ...
  e.stdout?.on("data",(l)=>c+=l),e.once("error",o),e.once("close",()=>r(c))
  ```

  There is no `timeout`, no `AbortSignal`, and no kill on any path. Another `ps -A` call in the same
  binary does pass one (`at("ps",["-A",...],{timeout:e,...})`), so the codebase already has a
  bounded pattern for this.

**Repro sketch.** Load macOS until a full-table `ps -A` takes over 30 s (we see that at load
averages of 300-600 on a 10-core M1 Max MacBook Pro). Run hooks that time out or get cancelled, then exit the
session. Count `ps` children of the `claude` pid.

**Suggested fix.** Give the spawn a timeout and kill the child when it expires (or pass an
`AbortSignal`), and treat a timed-out walk as "tree unknown" instead of waiting. A cheaper
option on macOS is to walk only the session's own descendants, e.g. `pgrep -P <pid>` recursively,
which avoids a full-table `ps`.

---

Before posting, remove any local paths, and confirm the snippet still matches the release named
in "Version".
