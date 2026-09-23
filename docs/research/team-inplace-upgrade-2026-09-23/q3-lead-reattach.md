# Q3 — does a RESUMED lead re-attach to its existing team? (2.1.280, measured 2026-09-23)

## Verdict
1. **Same team NAME, NEW team FILE.** Startup calls `initializeSessionTeam(void 0, …)` for every
   interactive non-teammate session; the name is `session-<K().slice(0,8)>` and on `--resume` K() is
   already the resumed sid, so the name is unchanged. But with no `existingTeamName` the function
   **unconditionally writes a leader-only `config.json`** (`TRn`, precondition `none`) — every member
   the previous process spawned is dropped from the file, and `createdAt` resets.
2. **In-memory roster is leader-only** after resume (`teamContext.teammates = {team-lead}`).
3. **SendMessage to a prior member works IFF the member is back in `config.json`:** the resolver
   checks the in-memory roster, then falls back to reading the team file (`ph`) and resolving the name
   there; not found ⇒ `not_reachable`, nothing sent.
4. **The resumed lead re-registers the team for session-end cleanup** (`Tcr`), so its NEXT exit kills
   every pane-backed member listed in the file and deletes the team dir — the same as before.
5. ⇒ Procedure: **snapshot the team dir before the lead's exit, restore the non-leader members (and
   inboxes) into the fresh file after the relaunched lead is up.**

## Evidence (strings of `~/.claude-280/…/bin/claude.exe`, extracted to one text file)

- Startup call site (CLI action): `let W;if(so()&&!Te()&&!u.agentId)try{let{initializeSessionTeam:j}=
  await import("/$bunfs/root/chunk-st2986zy.js");W=await j(void 0,R)}catch(j){d(j)}` — `void 0` means
  no `existingTeamName`; a teammate (`u.agentId`) never runs it.
- `initializeSessionTeam` (`export{x as initializeSessionTeam}`):
  `var l="session";function c(t){return`${l}-${t.slice(0,8)}`}` … `let i=t?.existingTeamName||p(),
  e=i??c(K())` … `if(!(i?await ph(e,n):null)){let r={name:e,createdAt:Date.now(),leadAgentId:a,
  leadSessionId:K(),members:[{…name:Ds,…tmuxPaneId:"leader",…backendType:"in-process"}]};await TRn(e,r,n)…}`
  `…jto(e);…await PEt(e,n),Tcr(e);…return{teamContext:{teamName:e,…teammates:{[a]:{name:Ds,…}}}}`.
  `p()` is only `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME`; unset here ⇒ `i` is null ⇒ the write always runs.
- `TRn` = `n.write(j(e),b(r,null,2),{precondition:{type:"none"}})` or plain `te($_e(e), …)` — an
  overwrite, not create-if-absent.
- `Tcr(e){pUn().add(e)}`; session end runs `BRo` → `cleanupSessionTeams: removing N orphan team dir(s)`
  → `me()` = `members.filter(c=>c.name!==Ds&&c.tmuxPaneId&&c.backendType&&y9t(c.backendType))` then
  `getBackendByType(c.backendType).killPane(c.tmuxPaneId, …)`, then `de()` = `rm -rf` the team dir
  (inboxes included). Keyed on the FILE's members, not on memory.
- SendMessage resolver `ut(...)`: `U=w.teamContext?.teammates??{}` … `ie=…Object.values(U).some(te=>
  te.name===s)` … `else if(!ie){let te=await ph(v,i.storageV5);if(te!==null){… X=…ren(PHe(te,…),s);
  if(X===void 0){… not_reachable`.
- Inbox path: `IO(e,n)` = `<cfg>/teams/<team>/inboxes/<agentName>.json` — keyed on NAME, so a
  relaunched teammate with the same `--agent-name` reads the same inbox.

## On-disk corroboration
`~/.claude-tertiary/teams/session-43055acd/config.json` — pane 495's lead, resumed onto 2.1.280 by
`cc-lr upgrade` at 2026-09-23T02:17Z — has `createdAt` = 02:17:15Z and exactly 1 member. Every lead
resumed today shows the same shape (createdAt = its resume time, members=1). Proven by effect in the
throwaway-team probe (see `probe.md`).
