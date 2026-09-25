// tools/hero-film/film.js: the README hero launch film for claude-infrastructure, as a pure function
// of time. Design record: tools/hero-film/README.md.
//
//   ?cut=loop   the README hero, an animated WebP (camera locked between flights)
//   ?cut=film   the launch film, an MP4 (one camera that never stops)
//   ?theme=dark|light, tuned to GitHub's page colours so the frame edge vanishes.
//
// Structure (adapted from agent-context-sync film/film.js, round 3). STORY is one land on its own
// clock s. It is CYCLIC: the peer splits and later folds, pills pass the gate and become history on
// a trunk that moves one commit spacing per land, the racks go stale and light again. So the state at
// s = END is the state at s = 0, and the camera can stay in one stretch of the world: the loop ends
// on its first frame with nothing undone. A cut is an edit list: each edit holds a pose or flies
// between two, shows a line of type, and maps film time t to story time s.

import { THEMES, clamp01, e, ease, lerp, p } from './lib.js'
import { drawWindow } from './panes.js'
import { FLEET, HERO, HH, HW, LIFT, RACK_X, RACK_Z, buildWorld, heroFoot } from './world.js'

const q = new URLSearchParams(location.search)
const THEME = q.get('theme') === 'light' ? 'light' : 'dark'
const CUT = q.get('cut') === 'film' ? 'film' : 'loop'
const T = THEMES[THEME]
for (const [k, v] of Object.entries(T)) if (typeof v === 'string') document.documentElement.style.setProperty(`--${k}`, v)
document.documentElement.dataset.theme = THEME

const W = 1920
const H = 1080
const stage = document.getElementById('stage')
const layer = document.createElement('div')
layer.style.position = 'absolute'
layer.style.inset = '0'

// ------------------------------------------------------------------------------------ the story
// One land, in story seconds. Every row a viewer can read is a real string (README § Honesty rule).
const S = {
  // Frame 0 is the END state of the last land, at s = start. The originator's scrollback clears at
  // s = clear, inside the first flight's blur, so the story begins at a bare prompt and the peer's
  // ping appears once, at the end (critique round two, blocker 1: result before cause).
  start: -0.3, clear: -0.15,
  // A session fires a peer: /handoff, the fire command, the split, the peer boots and reads its brief.
  type: [0.0, 0.35], submit: 0.4, say1: 0.5, fire: [0.6, 0.95], divider: [1.0, 1.35], boot: [1.35, 1.9],
  brief: [1.85, 2.05], peerLine: [1.6, 2.2], say2: 2.15, peerSay: 2.4,
  // The yard: fleet commits through the land-lock one at a time; a force push refused.
  work: [3.1, 3.9, 4.7, 5.5],
  passes: [3.6, 4.4, 5.2, 6.0, 6.55],
  force: { go: 3.65, hit: 4.4, wall: [4.1, 4.36], red: 4.4, fade: [5.3, 5.8], wallFade: [5.5, 6.0] },
  // The close: a false "done" sent back; the one decision rises to the human.
  done: 6.8, hook: 7.2, strike: [7.2, 7.45], notYet: 7.7, peerGo: 7.9, card: [8.3, 9.1],
  // The land: through the gate onto origin/main, verified by content; the live layer converges.
  peerPass: 9.4, stale: [9.8, 9.95], verified: 10.1, deploy: 10.55, pulse: [10.6, 11.0], lit: [11.0, 12.0],
  // The return: the peer's close, its ping, and its pane folding shut.
  safe: 12.3, ping: [12.6, 12.95], fold: [13.1, 13.55], lineFade: [13.2, 13.7],
  END: 14.0,
}
const PASSES = [...S.passes, S.peerPass] // every commit through the gate this land, in order
const PASS_T = 0.4 // gate to the trunk's head
const FLEET_PILLS = [7, 3, 9, 0, 10] // which fleet windows commit this land, in pass order

// The originator's rows, one land's worth. Three lands are stacked so the pane's visible tail is the
// same at s = 0 and s = END (it shows well under two lands of rows).
const PING_HEAD = 'PING RECEIVED FROM PEER — '
const LAND_ROWS = [
  { kind: 'user', text: '/handoff', at: S.submit },
  { kind: 'say', text: 'Firing a peer to build the README hero film.', at: S.say1 },
  { kind: 'tool', text: 'scripts/handoff-fire.sh --prompt-file /tmp/fire-readme-hero-film.txt --split-right --notify-back', at: S.fire[0], reveal: S.fire },
  { kind: 'say', text: 'Peer fired in a split-right pane. Waiting for its ping.', at: S.say2 },
  { kind: 'ping', head: PING_HEAD, text: `${PING_HEAD}HANDOFF-PING fire-readme-hero-film: landed on origin/main, verified by content — self-retiring.`, at: S.ping[0], reveal: S.ping },
]
// The peer: this film's own session. Its brief is the brief this film was made from.
const PEER_ROWS = [
  { kind: 'user', text: 'You are building the README hero LAUNCH FILM for claude-infrastructure (public repo github.com/renchris/claude-infrastructure). Your cwd is a fresh worktree on branch feat/readme-hero-film off origin/main.', at: S.brief[0], reveal: S.brief },
  { kind: 'say', text: "I'll start by reading the operator rulings and the sister repo's pipeline.", at: S.peerSay },
  { kind: 'greek', lines: 2, at: S.work[0] },
  { kind: 'greek', lines: 3, at: S.work[1] },
  { kind: 'greek', lines: 1, at: S.work[2] },
  { kind: 'greek', lines: 2, at: S.work[3] },
  { kind: 'say', text: 'Done.', at: S.done, strike: S.strike },
  { kind: 'hook', text: 'Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts it', at: S.hook, reveal: [S.hook, S.hook + 0.2] },
  { kind: 'say', text: 'Not landed yet. Running /ship.', at: S.notYet },
  { kind: 'close', text: '✅ SAFE TO CLOSE — nothing of mine is open', at: S.safe },
]
function rowsAt(list, s) {
  return list
    .filter((r) => s >= r.at)
    .map((r) => ({ ...r, reveal: r.reveal ? p(s, r.reveal[0], r.reveal[1]) || (s >= r.reveal[1] ? 1 : 0.001) : 1, strike: r.strike ? e(s, r.strike[0], r.strike[1], ease.travel) : 0 }))
}
function originRows(s) {
  return s < S.clear ? LAND_ROWS.map((r) => ({ ...r, reveal: 1 })) : rowsAt(LAND_ROWS, s)
}

/** Everything about the land at story time s. */
function landState(s) {
  const split = s < S.divider[0] ? 1 : s < S.fold[0] ? 0.5 : lerp(0.5, 1, e(s, S.fold[0], S.fold[1], ease.travel))
  const st = {
    s,
    split,
    draw: e(s, S.divider[0], S.divider[1], ease.travel),
    boot: e(s, S.boot[0], S.boot[1], ease.walk),
    typing: s < S.submit ? { text: '/handoff', reveal: p(s, S.type[0], S.type[1]) } : null,
    peerLine: e(s, S.peerLine[0], S.peerLine[1], ease.travel),
    peerLineA: 1 - e(s, S.lineFade[0], S.lineFade[1], ease.travel),
    peerLanded: s >= S.peerPass + PASS_T ? 1 : 0,
  }
  // The gate's arm lifts for each pass.
  st.arm = Math.max(0, ...PASSES.map((g) => e(s, g - 0.28, g - 0.08, ease.travel) * (1 - e(s, g + 0.22, g + 0.42, ease.travel))))
  // Fleet pills: out of their window along the line, into the gate's mouth, through, onto the trunk.
  st.pills = FLEET_PILLS.map((n, i) => pillOn('line', n, s, PASSES[i] - 2.0, PASSES[i]))
  st.peerPill = pillOn('peer', 0, s, S.peerGo, S.peerPass)
  // The force push: straight for origin/main, around the gate; stopped by the deny wall.
  const F = S.force
  st.force = s < F.go || s > F.fade[1] ? null : { on: 'force', u: 0.49 * ease.travel(p(s, F.go, F.hit)), a: 1 - e(s, F.fade[0], F.fade[1], ease.travel), red: s >= F.red ? 1 : 0 }
  st.wall = e(s, F.wall[0], F.wall[1], ease.settle) * (s < F.wallFade[1] ? 1 : 0)
  st.wallA = 1 - e(s, F.wallFade[0], F.wallFade[1], ease.travel)
  // The conveyor: every pass moves origin/main's history one spacing on.
  st.conveyor = PASSES.reduce((n, g) => n + e(s, g, g + PASS_T, ease.travel), 0)
  // The card rises out of the originator's pane.
  st.card = s < S.clear ? { ...cardAt(S.END), a: 1 - p(s, S.start, S.clear) } : s < S.card[0] ? null : cardAt(s)
  // The live layer: stale the moment the land reaches trunk; lit again, file by file, by the converger.
  st.stale = s >= S.stale[0] && s < S.lit[1] ? 1 : 0
  st.wave = s < S.lit[0] ? (s < S.stale[0] ? 1 : 0) : e(s, S.lit[0], S.lit[1], ease.walk)
  st.pulse = s >= S.pulse[0] && s < S.pulse[1] ? p(s, S.pulse[0], S.pulse[1]) : null
  st.heroSig = heroSig(s)
  return st
}
function pillOn(on, n, s, born, pass) {
  if (s < born || s >= pass + PASS_T) return null
  if (s < pass) return { on, n, u: 0.985 * ease.soft(p(s, born, pass - 0.1)), a: e(s, born, born + 0.25) }
  return { on: 'trunk', n, u: ease.travel(p(s, pass, pass + PASS_T)), a: 1, green: 1 }
}
// The originator's window is redrawn only when what it shows changes.
function heroSig(s) {
  const q2 = (x) => Math.round(x * 60)
  return [q2(Math.min(s, S.END)), THEME].join(':')
}

// The card, in the originator's window's own frame: it leaves the left pane and settles to its left,
// in front of the window, facing the lens.
const R_ = (HERO.deg * Math.PI) / 180
const NX = Math.sin(R_)
const NZ = Math.cos(R_)
const RX = Math.cos(R_)
const RZ = -Math.sin(R_)
const hl = (lx, ly, lz) => [HERO.x + RX * lx + NX * lz, ly, HERO.z + RZ * lx + NZ * lz]
function cardAt(s) {
  const u = ease.travel(p(s, S.card[0], S.card[1]))
  const a = hl(-HW / 4, LIFT + HH * 0.55, 0.1)
  const b = hl(-HW / 4 - 0.35, LIFT + HH * 0.6, 1.9)
  const c = hl(-HW / 4 - 0.6, LIFT + HH + 0.9, 0.8) // the arc's control point: up and out, then down to the lens
  const j = 1 - u
  const at = (i) => j * j * a[i] + 2 * j * u * c[i] + u * u * b[i]
  return {
    x: at(0), y: at(1), z: at(2), yaw: R_,
    scale: lerp(0.25, 1, ease.settle(p(s, S.card[0], S.card[1] - 0.1))),
    a: e(s, S.card[0], S.card[0] + 0.2),
    tether: 0, x0: a[0], z0: a[2],
  }
}

function drawHero(c, st) {
  const s = st.s
  const g = c.getContext('2d')
  const left = {
    font: 30, acct: HERO.acct, sess: 'claude-infrastructure (4f2ef1b9)', status: 'high', anchor: 'bottom', greekSeed: 3,
    rows: originRows(s), typing: st.typing, pingAcct: HERO.peerAcct,
  }
  const right = {
    font: 30, acct: HERO.peerAcct, sess: 'claude-infrastructure (dec7f8dc)', status: 'high', anchor: 'bottom', greekSeed: 11,
    boot: st.boot, rows: s >= S.fold[1] ? [] : rowsAt(PEER_ROWS, s),
    header: { version: 'v2.1.280', model: 'Opus 5.5 · Claude Max', cwd: '~/…/.worktrees/feat/readme-hero-film' },
  }
  drawWindow(g, T, c.width, c.height, {
    title: st.split < 0.999 ? '✳ Claude Code — 2 panes' : '✳ Claude Code',
    panes: st.split < 0.999 ? [left, right] : [left],
    split: st.split < 0.999 ? st.split : null,
    draw: st.draw,
  })
}

// ------------------------------------------------------------------------------------ cameras
// A pose is a position, a point it looks at, a focal length F (px) and a principal point (cx, cy).
const POSES = {
  // The poster: eye height, left of the originator's window, which stands on the right third; the
  // fleet's lines sweep past it into the gate.
  poster: { p: [12, 8, 31], at: [2.5, 0, 6], F: 1300, cx: 1300, cy: 480 },
  // The split: front-on, close.
  split: { p: hl(0.35, 1.7, 6.4), at: hl(0.2, 1.47, 0), F: 1650, cx: 1010, cy: 660 },
  // The yard: high behind the fan's right flank, the gate and the trunk ahead.
  yard: { p: [11.5, 8.2, 17.0], at: [-1.8, 0.4, -1.0], F: 1400, cx: 1000, cy: 610 },
  // The close: on the peer's pane, with room on the left for the card.
  close: { p: hl(-0.5, 1.8, 6.9), at: hl(0.15, 1.45, 0), F: 1500, cx: 1010, cy: 700 },
  // The racks: after the gate, a 3/4 on ~/.claude with the trunk running in.
  racks: { p: [8.5, 4.6, RACK_Z + 17], at: [-0.2, 2.0, RACK_Z], F: 1800, cx: 880, cy: 790 },
  // FILM only: each key is a neighbour of a LOOP pose, so the camera keeps drifting through it.
  posterIn: { p: [11.3, 7.55, 29.4], at: [2.5, 0, 6], F: 1300, cx: 1300, cy: 480 },
  splitB: { p: hl(0.3, 1.66, 5.9), at: hl(0.2, 1.47, 0), F: 1650, cx: 1010, cy: 660 },
  rise: { p: [15, 10.5, 32], at: [0.5, 0, 5], F: 1250, cx: 1000, cy: 560 },
  // Waypoints that keep the camera in front of the originator's window, never through it.
  swing: { p: [19, 5.5, 22], at: hl(0, 1.5, 0), F: 1400, cx: 1000, cy: 600 },
  hop: { p: [9, 7.0, 27], at: [1.5, 0.4, 4], F: 1350, cx: 1000, cy: 620 },
  yardB: { p: [10.4, 7.8, 16.0], at: [-1.8, 0.4, -1.0], F: 1400, cx: 1000, cy: 610 },
  gate: { p: [7.8, 4.6, 10.5], at: [-1.2, 0.8, -0.5], F: 1450, cx: 1000, cy: 640 },
  gateB: { p: [7.1, 4.3, 9.5], at: [-1.2, 0.8, -0.5], F: 1450, cx: 1000, cy: 640 },
  closeB: { p: hl(-0.4, 1.78, 6.4), at: hl(0.15, 1.45, 0), F: 1500, cx: 1010, cy: 700 },
  card: { p: hl(-1.9, 2.3, 6.2), at: hl(-1.5, 1.85, 1.9), F: 1500, cx: 1060, cy: 660 },
  trunk: { p: [4.2, 2.6, 5.0], at: [-0.3, 0.4, -7], F: 1350, cx: 1000, cy: 640 },
  racksB: { p: [7.9, 4.4, RACK_Z + 15.8], at: [-0.2, 2.0, RACK_Z], F: 1800, cx: 880, cy: 790 },
  over: { p: [24, 13, 14], at: [0, 0, 8], F: 1150, cx: 1000, cy: 560 },
}
// A pose can be overridden from the URL while composing: ?pose=name:{"p":[...],...}
if (q.get('pose')) {
  const [name, json] = q.get('pose').split(/:(.*)/s)
  Object.assign(POSES[name], JSON.parse(json))
}
function toCam(c) {
  const d = [c.at[0] - c.p[0], c.at[1] - c.p[1], c.at[2] - c.p[2]]
  const yaw = Math.atan2(d[0], -d[2])
  const pitch = Math.atan2(-d[1], Math.hypot(d[0], d[2]))
  return { x: c.p[0], y: c.p[1], z: c.p[2], yaw, pitch, F: c.F, cx: c.cx, cy: c.cy }
}
// A flight: from pose a to pose b along a curve through `via` (an offset from the straight line's
// midpoint), eased so it leaves and arrives at rest.
function fly(a, b, k, via = [0, 0, 0], viaAt = [0, 0, 0]) {
  const j = 1 - k
  const bez = (A, B, off) => A.map((v, i) => j * j * v + 2 * j * k * ((v + B[i]) / 2 + off[i]) + k * k * B[i])
  return { p: bez(a.p, b.p, via), at: bez(a.at, b.at, viaAt), F: lerp(a.F, b.F, k), cx: lerp(a.cx, b.cx, k), cy: lerp(a.cy, b.cy, k) }
}
// The FILM's camera never stops until its last frame: a monotone cubic (PCHIP) through key poses,
// leaving the first key from rest and arriving on the last at rest (sister repo, round 3).
const flat = (c) => [...c.p, ...c.at, c.F, c.cx, c.cy]
const unflat = (v) => ({ p: v.slice(0, 3), at: v.slice(3, 6), F: v[6], cx: v[7], cy: v[8] })
function pathCam(keys, t) {
  const P = keys.map((k) => flat(POSES[k.pose]))
  const n = keys.length
  const found = keys.findIndex((k, j) => j < n - 1 && t < keys[j + 1].t)
  const i = found < 0 ? n - 2 : found
  const slope = (a, c) => (P[a + 1][c] - P[a][c]) / (keys[a + 1].t - keys[a].t)
  const tangent = (j, c) => {
    if (j === n - 1 || j === 0) return 0
    const d0 = slope(j - 1, c)
    const d1 = slope(j, c)
    if (d0 * d1 <= 0) return 0
    const h0 = keys[j].t - keys[j - 1].t
    const h1 = keys[j + 1].t - keys[j].t
    const w1 = 2 * h1 + h0
    const w2 = h1 + 2 * h0
    return (w1 + w2) / (w1 / d0 + w2 / d1)
  }
  const h = keys[i + 1].t - keys[i].t
  const u = clamp01((t - keys[i].t) / h)
  const h00 = 2 * u ** 3 - 3 * u ** 2 + 1
  const h10 = u ** 3 - 2 * u ** 2 + u
  const h01 = -2 * u ** 3 + 3 * u ** 2
  const h11 = u ** 3 - u ** 2
  return unflat(P[i].map((v, c) => h00 * v + h10 * h * tangent(i, c) + h01 * P[i + 1][c] + h11 * h * tangent(i + 1, c)))
}

// ------------------------------------------------------------------------------------ the type
const scrim = document.createElement('div')
Object.assign(scrim.style, { position: 'absolute', left: '0', top: '0', width: '1920px', height: '420px', background: 'linear-gradient(to bottom, var(--bg) 0, var(--bg) 150px, color-mix(in srgb, var(--bg) 70%, transparent) 290px, transparent 420px)' })
layer.append(scrim)
// On the poster the type has the left of the frame: a horizontal scrim keeps the world quiet behind it.
const side = document.createElement('div')
Object.assign(side.style, { position: 'absolute', left: '0', top: '0', width: '1920px', height: '1080px', background: 'linear-gradient(to right, var(--bg) 0, var(--bg) 560px, color-mix(in srgb, var(--bg) 78%, transparent) 900px, transparent 1180px)' })
layer.append(side)
function el(cls, style, html = '') {
  const d = document.createElement('div')
  d.className = `t ${cls}`
  Object.assign(d.style, style)
  d.innerHTML = html
  layer.append(d)
  return d
}
/** Split a line of type into word spans, so it can move word by word. */
function words(d) {
  const parts = []
  const walk = (node) => {
    for (const ch of [...node.childNodes]) {
      if (ch.nodeType === 3) {
        const frag = document.createDocumentFragment()
        ch.textContent.split(/(\s+)/).forEach((w) => {
          if (!w) return
          if (/^\s+$/.test(w)) frag.append(document.createTextNode(w))
          else {
            const sp = document.createElement('span')
            sp.className = 'w'
            sp.textContent = w
            frag.append(sp)
            parts.push(sp)
          }
        })
        ch.replaceWith(frag)
      } else if (ch.nodeType === 1 && ch.classList.contains('mono')) {
        ch.classList.add('w')
        parts.push(ch)
      } else walk(ch)
    }
  }
  walk(d)
  d._words = parts
  return d
}
const mono = (s) => `<span class="mono">${s}</span>`
const mark = el('mono', { left: '112px', top: '78px', fontSize: '34px', color: 'var(--muted)', letterSpacing: '-0.01em' }, 'claude-infrastructure')
// The governing thought, three tiers: what it is, how it runs, what is left for you.
const g1 = words(el('', { left: '110px', top: '262px', fontSize: '62px', fontWeight: '500', letterSpacing: '-0.03em', color: 'var(--ink)' }, `${mono('~/.claude')}, deployed from git.`))
const g2 = words(el('', { left: '104px', top: '356px', fontSize: '112px', fontWeight: '600', lineHeight: '0.98', letterSpacing: '-0.045em', color: 'var(--ink)' }, 'The sessions run<br>each other.'))
const g3 = words(el('', { left: '104px', top: '600px', fontSize: '112px', fontWeight: '600', lineHeight: '0.98', letterSpacing: '-0.045em', color: 'var(--ink)' }, 'You only decide.'))
g1.querySelectorAll('.mono').forEach((m) => Object.assign(m.style, { letterSpacing: '-0.05em', fontWeight: '500' }))
const THOUGHT = [g1, g2, g3]
const LINES = {
  split: ['A session fires a peer.'],
  yard: ['Every session in its own lane.<br>One land at a time.'],
  close: ['“Done” is checked.<br>Only decisions reach you.'],
  racks: ['Landed is not live<br>until the running bytes match.'],
  // FILM only.
  lanes: ['Every session in its own lane.'],
  gate: ['One land at a time.<br>A dangerous call never runs.'],
  checked: ['“Done” is checked, not believed.'],
  decide: ['Only decisions reach you.'],
}
const lines = {}
for (const [k, [text]] of Object.entries(LINES)) {
  lines[k] = words(el('', { left: '108px', top: '158px', fontSize: '80px', fontWeight: '600', letterSpacing: '-0.04em', color: 'var(--ink)', lineHeight: '1.04' }, text))
}
// Chips: labels on world objects, in the colour their object means.
const chipStyle = { fontSize: '30px', lineHeight: '1', padding: '7px 13px 10px', borderRadius: '10px', border: '3px solid var(--faint)', background: 'var(--bg)', color: 'var(--ink)' }
const chips = {
  peer: el('mono', { ...chipStyle, color: T.acct[HERO.peerAcct], borderColor: T.acct[HERO.peerAcct] }, `account ③ · feat/readme-hero-film`),
  force: el('mono', { ...chipStyle, fontSize: '32px' }, 'git push --force'),
  denied: el('', { ...chipStyle, fontFamily: 'Geist', fontWeight: '600', fontSize: '32px', color: 'var(--red)', borderColor: 'var(--red)' }, 'denied: it never runs'),
  verified: el('', { ...chipStyle, fontFamily: 'Geist', fontWeight: '600', color: 'var(--green)', borderColor: 'var(--green)' }, 'on origin/main · verified by content'),
  deploy: el('mono', { ...chipStyle, color: 'var(--ink)' }, 'deploy-live.sh'),
  acct: T.acct.map((c, a) => el('mono', { ...chipStyle, fontSize: '26px', padding: '5px 10px 8px', color: c, borderColor: c }, `account ${'①②③④'[a]}`)),
  // The hook that refused the false "done": its real file name, in the colour of a refusal.
  hook: el('', { ...chipStyle, fontFamily: 'Geist', fontWeight: '600', fontSize: '32px', color: 'var(--red)', borderColor: 'var(--red)' }, `“Done.” sent back by <span class="mono" style="font-weight:500">hooks/completion-assert.sh</span>`),
}

// ------------------------------------------------------------------------------------ the edits
// An edit holds `cam` (a pose) or flies `fly: [from, to]`, and maps film time to story time:
// s = s0 + (t - from) * rate. The LOOP's camera is locked between flights, because an animated WebP
// has no motion compensation: a still frame is nearly free and a moving one costs about 1 MB a second.
const LOOP = [
  { from: 0, to: 2.6, cam: 'poster', s0: S.start, rate: 0, poster: true },
  // The reset (scrollback cleared, the card delivered) happens inside this flight's blur.
  { from: 2.6, to: 3.4, fly: ['poster', 'split'], via: [0, 0.3, 0], s0: S.start, rate: 0.375, blur: true },
  { from: 3.4, to: 6.0, cam: 'split', line: 'split', s0: 0, rate: 1.0, chip: ['peer'] },
  { from: 6.0, to: 6.9, fly: ['split', 'yard'], via: [3, 5, 6], viaAt: [0, 0, 0], s0: 2.6, rate: 0.44, blur: true },
  { from: 6.9, to: 9.9, cam: 'yard', line: 'yard', s0: 3.0, rate: 1.1, chip: ['force', 'denied', 'accounts'] },
  { from: 9.9, to: 10.8, fly: ['yard', 'close'], via: [2, 4, 4], s0: 6.3, rate: 0.33, blur: true },
  { from: 10.8, to: 13.8, cam: 'close', line: 'close', s0: 6.6, rate: 0.93, chip: ['hook'] },
  // Up first, so the camera clears the card it leaves hanging in front of the window.
  { from: 13.8, to: 14.7, fly: ['close', 'racks'], via: [2, 10, 18], s0: 9.39, rate: 0.68, blur: true },
  { from: 14.7, to: 16.9, cam: 'racks', line: 'racks', s0: 10.0, rate: 1.0, chip: ['verified', 'deploy'] },
  // REKEY: this flight's background is two levels off (invisible), so every pixel of the poster that
  // follows differs from the frame before it and the encoder re-sends the poster whole (sister repo).
  // The peer's close, its ping and the fold play out as the camera decelerates into the poster, so the
  // held poster that follows is still (critique round two: the fold read as a pop on a still hold).
  { from: 16.9, to: 18.0, fly: ['racks', 'poster'], via: [6, 9, 8], viaAt: [0, -1, 6], s0: 12.2, rate: 1.8 / 1.1, blur: true, rekey: true },
  { from: 18.0, to: 19.4, cam: 'poster', s0: S.END, rate: 0, poster: true, arrive: true },
]
// The FILM: one camera path that never stops until it arrives back on frame 0. Edits carry only the
// story clock and the type; the camera comes from FILM_PATH.
const FILM = [
  { from: 0, to: 2.4, s0: S.start, rate: 0, poster: true, typeIn: null },
  { from: 2.4, to: 6.4, s0: -0.6, rate: 0.8, line: 'split', chip: ['peer'] },
  { from: 6.4, to: 9.6, s0: 2.6, rate: 0.28, line: 'lanes' },
  { from: 9.6, to: 13.2, s0: 3.5, rate: 0.83, line: 'gate', chip: ['force', 'denied', 'accounts'] },
  { from: 13.2, to: 16.4, s0: 6.4, rate: 0.44, line: 'checked', chip: ['hook'] },
  { from: 16.4, to: 19.4, s0: 7.81, rate: 0.46, line: 'decide' },
  // Its line waits until the camera is through the gate, so no sign crosses the caption band.
  { from: 19.4, to: 25.2, s0: 9.2, rate: 0.52, line: 'racks', chip: ['verified', 'deploy'], typeIn: [22.0, 22.6] },
  // The return: the camera climbs over the racks and swings round to the fleet's faces; the ping and
  // the fold are timed into the final approach, where the originator's window faces the lens.
  { from: 25.2, to: 27.8, s0: 12.22, rate: 0.108 },
  { from: 27.8, to: 30.0, s0: 12.5, rate: 0.68, poster: true, typeIn: [28.3, 29.2], typeOut: null, arrive: true },
]
const FILM_PATH = [
  { t: 0, pose: 'poster' },
  { t: 2.4, pose: 'posterIn' },
  { t: 3.6, pose: 'split' },
  { t: 6.2, pose: 'splitB' },
  { t: 8.2, pose: 'rise' },
  { t: 9.8, pose: 'yardB' },
  { t: 11.4, pose: 'gate' },
  { t: 13.0, pose: 'gateB' },
  { t: 14.0, pose: 'swing' },
  { t: 15.0, pose: 'close' },
  { t: 16.3, pose: 'closeB' },
  { t: 18.2, pose: 'card' },
  { t: 19.4, pose: 'hop' },
  { t: 20.6, pose: 'trunk' },
  { t: 22.4, pose: 'racks' },
  { t: 25.0, pose: 'racksB' },
  { t: 27.2, pose: 'over' },
  { t: 29.2, pose: 'poster' },
]
const EDITS = CUT === 'film' ? FILM : LOOP
const DURATION = EDITS[EDITS.length - 1].to
const SHUTTER = Number(q.get('shutter') ?? 1 / 120)
const SUBS = Number(q.get('subs') ?? 6) // 6 sub-frames: 4 strobed a post the camera passed close to

// ------------------------------------------------------------------------------------ one frame
let world = null
function editAt(t) {
  return EDITS.find((x) => t >= x.from && t < x.to) ?? EDITS[EDITS.length - 1]
}
function storyAt(ed, t) {
  const s = ed.s0 + (t - ed.from) * (ed.rate ?? 0)
  return Math.max(S.start, Math.min(S.END, s))
}
function camAt(ed, t) {
  if (CUT === 'film') return pathCam(FILM_PATH, t)
  if (ed.cam) return POSES[ed.cam]
  const k = ease.travel(p(t, ed.from, ed.to))
  return fly(POSES[ed.fly[0]], POSES[ed.fly[1]], k, ed.via, ed.viaAt)
}
const REST = landState(S.start)
// Ambient commits: while the poster holds, three commits crawl toward the gate, so the poster reads as
// a running system and not a still (critique round two, finding 9). tau is time from the seam, so
// their positions agree on both sides of it; they fade out inside the flights either side.
const AMBIENT = [{ n: 4, u0: 0.42 }, { n: 9, u0: 0.3 }, { n: 3, u0: 0.55 }]
function ambientAt(t) {
  const tau = t < DURATION / 2 ? t : t - DURATION
  const reach = CUT === 'film' ? [-2.6, 3.4] : [-2.0, 3.0]
  if (tau < reach[0] || tau > reach[1]) return null
  const a = e(tau, reach[0], reach[0] + 0.5, ease.travel) * (1 - e(tau, reach[1] - 0.5, reach[1], ease.travel))
  return AMBIENT.map((m) => ({ on: 'line', n: m.n, u: m.u0 + 0.07 * tau, a }))
}
function applyWorld(t) {
  const ed = editAt(t)
  const s = storyAt(ed, t)
  world.pose(toCam(camAt(ed, t)))
  const cur = { ...landState(s), ambient: ambientAt(t) }
  world.update((k) => (k === 0 ? cur : REST), { fog: [34, 150], rekey: !!ed.rekey, drawHero })
  return { ed, s, st: cur }
}

function show(d, o = 1) {
  d.style.visibility = o > 0.001 ? 'visible' : 'hidden'
  d.style.opacity = o.toFixed(3)
}
function hideAll() {
  for (const d of layer.children) d.style.visibility = 'hidden'
}
/** Kinetic type: words arrive (k 0 -> 1) rising into place in turn, and leave drifting left. */
function kin(d, k, mode) {
  const ws = d._words
  const n = ws.length
  const stag = 0.16
  show(d, k > 0.001 ? 1 : 0)
  ws.forEach((w, i) => {
    const local = clamp01(k * (1 + stag * (n - 1)) - stag * (mode === 'out' ? n - 1 - i : i))
    if (mode === 'out') {
      // A line leaves whole: word by word, it left fragments that read as other sentences.
      const u = ease.leave(1 - clamp01(k))
      w.style.opacity = (1 - u).toFixed(3)
      w.style.transform = `translate(${(-60 * u).toFixed(1)}px, 0)`
    } else {
      const u = ease.settle(local)
      w.style.opacity = local.toFixed(3)
      w.style.transform = `translate(0, ${(34 * (1 - u)).toFixed(1)}px)`
    }
  })
}
let posterK = 0
function showType(x, k, mode) {
  if (!x || k <= 0.001) return
  if (x.poster) {
    THOUGHT.forEach((d) => kin(d, k, mode))
    posterK = Math.max(posterK, k)
  } else if (x.line) kin(lines[x.line], k, mode)
}
function typeAt(t, st) {
  hideAll()
  show(mark)
  posterK = 0
  const ed = editAt(t)
  document.documentElement.style.setProperty('--bg', ed.rekey ? T.bgRekey : T.bg)
  const i = EDITS.indexOf(ed)
  const prev = EDITS[i - 1]
  const next = EDITS[i + 1]
  const u = p(t, ed.from, ed.to)
  if (CUT === 'film') {
    const tin = ed.typeIn === undefined ? [ed.from, ed.from + 0.7] : ed.typeIn
    const tout = ed.typeOut === undefined ? [ed.to - 0.45, ed.to] : ed.typeOut
    if (tout && t >= tout[0]) showType(ed, 1 - p(t, tout[0], tout[1]), 'out')
    else showType(ed, tin ? p(t, tin[0], tin[1]) : 1, 'in')
  } else if (ed.fly) {
    // Across a flight the old line leaves over its first half and the new one arrives in its last
    // 40 %, word by word, so type is always in motion with the camera.
    showType(prev, 1 - p(u, 0, 0.5), 'out')
    // Into the poster the thought assembles during the flight itself, so the held poster that
    // follows is still apart from the window (those frames are stored near-lossless, and a moving
    // headline in them cost 6.3 MB of an 11 MB loop, measured round one).
    showType(next, p(u, next?.poster ? 0.45 : 0.62, 1), 'in')
  } else showType(ed, 1, 'in')
  show(scrim, 1 - posterK)
  show(side, posterK)
  // Chips, in the edit that names them.
  const want = new Set(ed.chip ?? [])
  const s = st.s
  const S0 = world.stretches.find((x) => x.k === 0)
  if (want.has('peer')) {
    const [fx, , fz] = hl(HW / 4, 0, 0.15)
    chipAt(chips.peer, fx, LIFT, fz, clamp01(st.peerLine * 2.2) * st.peerLineA, -200, 18)
  }
  if (want.has('force') && st.force) {
    const pt = world.pillPoint(S0, st.force)
    chipAt(chips.force, pt.x, 0.4, pt.z, st.force.a, 26, -86)
    chips.force.style.color = st.force.red ? T.red : T.ink
    chips.force.style.borderColor = st.force.red ? T.red : T.faint
  }
  if (want.has('denied') && st.wall > 0.01) chipAt(chips.denied, S0.wallAt.x, 1.55, S0.wallAt.z, st.wallA * e(s, S.force.red, S.force.red + 0.15), -10, -80)
  if (want.has('hook')) {
    // Under the peer's pane, so the struck "Done." and the hook's own row stay in view above it.
    const [x, y, z] = hl(HW / 4, LIFT, 0.15)
    chipAt(chips.hook, x, y, z, e(s, S.hook, S.hook + 0.15) * (1 - e(s, S.peerGo + 0.6, S.peerGo + 0.9, ease.travel)), -330, 18)
  }
  if (want.has('accounts')) {
    // Each account named once, in its own colour, on one of its lines.
    ;[6, 8, 3, 4].forEach((n, a) => {
      const pt = S0.lines[n].curve.getPointAt(0.3)
      chipAt(chips.acct[a], pt.x, 0, pt.z, 1, -40, -20)
    })
  }
  if (want.has('verified')) chipAt(chips.verified, 0, 0, RACK_Z + 4.2, e(s, S.verified, S.verified + 0.2), -560, -84)
  if (want.has('deploy')) chipAt(chips.deploy, RACK_X[2], 0, RACK_Z + 1.5, e(s, S.deploy, S.deploy + 0.2), 40, -46)
}
function chipAt(d, x, y, z, o, dx = 0, dy = 0) {
  const pt = world.project(x, y, z)
  if (!pt || o <= 0.001) return
  show(d, o)
  d.style.left = `${Math.max(24, Math.min(W - 24 - d.offsetWidth, Math.round(pt[0] + dx)))}px`
  d.style.top = `${Math.round(pt[1] + dy)}px`
}

function seek(t) {
  const ed = editAt(t)
  if ((ed.blur || CUT === 'film') && SUBS > 1) {
    const subs = Array.from({ length: SUBS }, (_, k) => () => applyWorld(Math.max(ed.from, Math.min(ed.to - 1e-4, t + ((k + 0.5) / SUBS - 0.5) * SHUTTER))))
    world.render(subs)
  } else {
    applyWorld(t)
    world.render(null)
  }
  const { st } = applyWorld(t)
  typeAt(t, st)
}

window.__duration = DURATION
// What the encoder needs to know: where the camera flies (film-encode-loop.py stores those frames
// lossy, at 20 fps) and which holds are the poster (stored near-lossless: frame 0 is the most-seen
// frame, and the seam is exact only if the poster decodes the same both times it is shown).
window.__meta = {
  cut: CUT,
  duration: DURATION,
  flights: EDITS.filter((x) => x.fly).map((x) => [x.from, x.to]),
  nearLossless: EDITS.filter((x) => x.poster && x.cam).map((x) => [x.from, x.to]),
}
const seekAny = (t) => seek(((t % DURATION) + DURATION) % DURATION)
Promise.all(['400 26px "Geist"', '500 26px "Geist"', '600 26px "Geist"', '400 26px "Geist Mono"', '500 26px "Geist Mono"', '600 26px "Geist Mono"'].map((f) => document.fonts.load(f))).then(() => document.fonts.ready).then(() => {
  world = buildWorld(T, { width: W, height: H })
  stage.append(world.renderer.domElement)
  stage.append(layer)
  window.__seek = seekAny
  window.__ready = true
  window.__seek(Number(q.get('t') ?? 0))
})

export { FLEET }
