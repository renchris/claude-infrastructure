<div align="center">

# Claude Code Infrastructure

### `~/.claude` becomes a system you deploy — and the sessions become the schedulers.

[![sessions](https://img.shields.io/badge/sessions-5%2C709-d4af37?style=flat-square&labelColor=161b22)](#4-nothing-a-session-did-dies-with-it)
[![hooks](https://img.shields.io/badge/hooks-69%20across%2012%20events-d4af37?style=flat-square&labelColor=161b22)](#3-autonomy-is-bounded)
[![tests](https://img.shields.io/badge/bats%20tests-2%2C307-d4af37?style=flat-square&labelColor=161b22)](#5-the-whole-system-deploys-from-git)
[![accounts](https://img.shields.io/badge/accounts-4%20isolated-d4af37?style=flat-square&labelColor=161b22)](#2-parallel-work-cannot-collide)

[**1 · Sessions run each other**](#1-sessions-run-each-other) · [**2 · No collisions**](#2-parallel-work-cannot-collide) · [**3 · Bounded autonomy**](#3-autonomy-is-bounded) · [**4 · Nothing is lost**](#4-nothing-a-session-did-dies-with-it) · [**5 · Deploys from git**](#5-the-whole-system-deploys-from-git) · [**Install**](#install)

</div>

Claude Code reads everything it does — permissions, hooks, commands, agents — from `~/.claude`.
But `~/.claude` is machine state: unversioned, unreviewable, and the moment a second session starts,
the two share one git index, one binary, and one operator's attention. **So how do you run many at
once, safely, unattended?**

Make `~/.claude` a *deployment* of a git repo — and make the sessions themselves the schedulers.
That is this repo: **620 files, ~119,000 lines**, held to ground truth by a **2,307-test** bats suite
and exercised across **5,709 sessions**.

<div align="center">

<img src="assets/demo/handoff-live.gif" width="900" alt="Screen recording of one real iTerm2 window in three captioned beats. One: a real Claude session runs handoff-fire.sh with --split-right --notify-back, and the pane splits. Two: a second Claude session boots in the new pane, reads its brief, gets origin/main = bebd9580, and reports the back-channel ping as verdict=delivered reason=wake-path-armed before running self-close --terminal. Three: the ping arrives inside the originator's own chat as PING RECEIVED FROM PEER with the peer's message, and the peer has closed its own pane — the window is back to one.">

<sub><b>An unedited screen recording — two real Claude sessions, one window.</b> A session fires a peer, the pane <b>splits</b>, the peer answers <code>origin/main = bebd9580</code> and <b>pings back</b>; the ping arrives <b>inside the originator's chat</b> (<code>PING RECEIVED FROM PEER</code>) and the peer <b>closes its own pane</b>. One human keystroke: the first prompt. <a href="assets/demo/handoff-live.mp4">Full-resolution video</a> — 1600×924, 30 fps.</sub>
</div>
