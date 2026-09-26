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

import { THEMES, clamp01, e, ease, hermite5, lerp, p } from './lib.js'
import { CARD_TEXT, drawWindow } from './panes.js'
import { FH, FLEET, HERO, HH, HW, LIFT, RACK_X, RACK_Z, buildWorld, heroFoot } from './world.js'

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
  // s = clear, as the camera leaves the poster, so the story begins at a bare prompt and the peer's
  // ping appears once, at the end (critique round two, blocker 1: result before cause).
  start: -0.3, clear: -0.15,
  // A session fires a peer: /handoff, the fire command, the split, the peer boots, reads its brief, works.
  type: [0.0, 0.35], submit: 0.4, say1: 0.5, fire: [0.6, 0.95], divider: [1.0, 1.35], boot: [1.35, 1.9],
  brief: [1.85, 2.05], peerLine: [1.6, 2.2], say2: 2.15, peerSay: 2.4,
  // The peer's work rows (greeked) arrive after the card, as the camera leaves: before round two's
  // critique they scrolled its brief, the proof it is a real session, off after 0.9 s.
  work: [4.35, 4.55, 4.75],
  // The one decision rises out of the originator's pane to the human.
  card: [3.35, 4.25],
  // The peer's commit leaves its window for the land-lock; the fleet's commits cross it one at a
  // time; a force push is refused (the FILM's gate scene); the peer's commit crosses last.
  peerGo: 4.3,
  passes: [5.5, 6.3, 7.1],
  force: { go: 5.3, hit: 6.1, wall: [5.8, 6.06], red: 6.1, fade: [8.8, 9.3], wallFade: [9.0, 9.5] },
  peerPass: 8.9,
  // The land: onto origin/main, verified by content; the live layer converges.
  stale: [9.3, 9.45], verified: 9.6, deploy: 10.05, pulse: [10.1, 10.5], lit: [10.5, 11.5],
  // The return: the peer's close, its ping, and its pane folding shut.
  safe: 11.8, ping: [12.1, 12.45], fold: [12.6, 13.05], lineFade: [12.7, 13.2],
  END: 13.5,
}
const PASSES = [...S.passes, S.peerPass] // every commit through the gate this land, in order
const PASS_T = 0.4 // gate to the trunk's head
const FLEET_PILLS = [7, 3, 9] // which fleet windows commit this land, in pass order

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
  { kind: 'greek', lines: 2, at: S.work[2] },
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
  st.force = CUT !== 'film' || s < F.go || s > F.fade[1] ? null : { on: 'force', u: 0.49 * ease.travel(p(s, F.go, F.hit)), a: 1 - e(s, F.fade[0], F.fade[1], ease.travel), red: s >= F.red ? 1 : 0 }
  st.wall = CUT !== 'film' ? 0 : e(s, F.wall[0], F.wall[1], ease.settle) * (s < F.wallFade[1] ? 1 : 0)
  st.wallA = 1 - e(s, F.wallFade[0], F.wallFade[1], ease.travel)
  // The conveyor: every pass moves origin/main's history one spacing on.
  st.conveyor = PASSES.reduce((n, g) => n + e(s, g, g + PASS_T, ease.travel), 0)
  // The card rises out of the originator's pane.
  st.card = s < S.clear ? { ...cardAt(S.END), a: 1 - ease.smoother(p(s, S.start, S.clear)) } : s < S.card[0] ? null : cardAt(s)
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
// The originator's window is redrawn only when what it shows changes. The clear is a step, so it is
// in the signature itself: at 1/60 story-second quantisation a blur sub-frame just before it drew the
// old scrollback under the cleared state's signature, and that stale canvas stuck (review sheet, round
// two).
function heroSig(s) {
  return [Math.round(Math.min(s, S.END) * 1000), s < S.clear ? 'pre' : 'post', THEME].join(':')
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
  const k = c.width / 2048 // world.js TEX: the canvas is drawn at k times round two's size
  const left = {
    font: 30 * k, acct: HERO.acct, sess: 'claude-infrastructure (4f2ef1b9)', status: 'high', anchor: 'bottom', greekSeed: 3,
    rows: originRows(s), typing: st.typing, pingAcct: HERO.peerAcct,
    // The last land's scrollback fades out with the card as the camera leaves the poster.
    rowsAlpha: s < S.clear ? 1 - ease.smoother(p(s, S.start, S.clear)) : 1,
  }
  const right = {
    font: 30 * k, acct: HERO.peerAcct, sess: 'claude-infrastructure (dec7f8dc)', status: 'high', anchor: 'bottom', greekSeed: 11,
    boot: st.boot, rows: s >= S.fold[1] ? [] : rowsAt(PEER_ROWS, s),
    header: { version: 'v2.1.280', model: 'Opus 5.5 · Claude Max', cwd: '~/…/.worktrees/feat/readme-hero-film' },
  }
  drawWindow(g, T, c.width, c.height, {
    k,
    title: st.split < 0.999 ? '✳ Claude Code — 2 panes' : '✳ Claude Code',
    panes: st.split < 0.999 ? [left, right] : [left],
    split: st.split < 0.999 ? st.split : null,
    draw: st.draw,
  })
}

// ------------------------------------------------------------------------------------ cameras
// A pose is a position, a point it looks at, a focal length F (px) and a principal point (cx, cy).
const POSES = {
  // The poster: a high 3/4 over the fleet; the originator's window large in the right foreground.
  poster: { p: [12, 8, 31], at: [2.5, 0, 6], F: 1300, cx: 1300, cy: 480 },
  // The window: the originator's kitty window, both panes once it splits, with room on the left for
  // the card that rises out of the left pane.
  window: { p: hl(-0.5, 1.8, 6.9), at: hl(0.15, 1.45, 0), F: 1500, cx: 1010, cy: 700 },
  // The racks: after the gate, a 3/4 on ~/.claude with the trunk running in. Round two framed it from
  // 1.8x further back on a 1.8x longer lens, turned a fifth of the way toward the poster: the racks are
  // the same size, and the two flights that reach them travel 13 % less (5,626 -> 4,864 px), which is
  // 13 % fewer 60 fps frames in the WebP's most expensive span.
  racks: { p: [14.0, 6.5, 10.3], at: [-0.2, 2.0, RACK_Z], F: 3240, cx: 880, cy: 790 },
  // FILM only: the gate, high over the land-lock with every lane converging on it.
  gate: { p: [11.5, 8.2, 17.0], at: [-1.8, 0.4, -1.0], F: 1400, cx: 1000, cy: 610 },
}
// FILM only: each held shot creeps (the camera never holds still), pushed in along its own line of
// sight and turned a touch, well under CALM; the poster pushes in THROUGH frame 0, so the film's last
// frame runs on into its first at the same pace.
const creep = (c, push, turn = 0) => {
  const o = orbitOf(c)
  return fromOrbit({ ...o, lr: o.lr - push, yaw: o.yaw + turn })
}
POSES.posterIn = creep(POSES.poster, 0.03)
POSES.posterOut = creep(POSES.poster, -0.034)
POSES.windowB = creep(POSES.window, 0.07, 0.02)
POSES.gateB = creep(POSES.gate, 0.05, -0.02)
POSES.racksB = creep(POSES.racks, 0.05, 0.015)
// A pose can be overridden from the URL while composing: ?pose=name:{"p":[...],...}
if (q.get('pose')) {
  const [name, json] = q.get('pose').split(/:(.*)/s)
  Object.assign(POSES[name], JSON.parse(json))
}
function toCam(c) {
  const d = [c.at[0] - c.p[0], c.at[1] - c.p[1], c.at[2] - c.p[2]]
  const yaw = Math.atan2(d[0], -d[2])
  const pitch = Math.atan2(-d[1], Math.hypot(d[0], d[2]))
  return { x: c.p[0], y: c.p[1], z: c.p[2], yaw, pitch, F: c.F, cx: c.cx, cy: c.cy, focus: Math.hypot(...d) }
}
// A move, as an orbit about the point the camera looks at: that point travels a curve (bent by
// viaAt), the camera's bearing and elevation from it turn evenly, and its distance changes evenly in
// LOG space, so a push from far to near reads at one pace instead of rushing at the end (round one's
// straight-line flights put most of their image motion into their last few frames). `hop` pulls the
// camera out mid-move (log units) and `rise` lifts it (radians), so a long move climbs, looks, and
// settles instead of sweeping low across the world.
function orbitOf(c) {
  const d = [c.p[0] - c.at[0], c.p[1] - c.at[1], c.p[2] - c.at[2]]
  const r = Math.hypot(...d)
  return { at: c.at, yaw: Math.atan2(d[0], d[2]), pitch: Math.asin(d[1] / r), lr: Math.log(r), F: c.F, cx: c.cx, cy: c.cy }
}
function fromOrbit(o) {
  const r = Math.exp(o.lr)
  const c = Math.cos(o.pitch)
  return { p: [o.at[0] + r * c * Math.sin(o.yaw), o.at[1] + r * Math.sin(o.pitch), o.at[2] + r * c * Math.cos(o.yaw)], at: o.at, F: o.F, cx: o.cx, cy: o.cy }
}
function pathAt(a, b, k, m = {}) {
  const A = orbitOf(a)
  const B = orbitOf(b)
  const j = 1 - k
  const via = m.viaAt ?? [0, 0, 0]
  const at = A.at.map((v, i) => j * j * v + 2 * j * k * ((v + B.at[i]) / 2 + via[i]) + k * k * B.at[i])
  let dyaw = B.yaw - A.yaw
  dyaw -= 2 * Math.PI * Math.round(dyaw / (2 * Math.PI))
  const bump = 4 * k * j
  return fromOrbit({
    at, yaw: A.yaw + dyaw * k, pitch: lerp(A.pitch, B.pitch, k) + (m.rise ?? 0) * bump, lr: lerp(A.lr, B.lr, k) + (m.hop ?? 0) * bump,
    F: lerp(A.F, B.F, k), cx: lerp(A.cx, B.cx, k), cy: lerp(A.cy, B.cy, k),
  })
}
// A move is timed by how far the PICTURE moves, not by its parameter: the image travel of a 3 x 3 grid
// of points at the subject's depth and of every named object on screen (the fastest one, per step),
// tabulated along the path, so the picture's speed follows the move's speed curve exactly and the
// camera slows wherever it passes close to something. That is what the pacing gate measures.
const GRID = [0.1, 0.5, 0.9].flatMap((u) => [0.1, 0.5, 0.9].map((v) => [u * W, v * H]))
let OBJ_REST = null // the named objects, the card where it rests (set once the world exists)
// Each measure against its own bound (scripts/hero-film-pacing.py): the subject's depth at MAX_FLOW,
// 900 px/s; a named object at MAX_SWEEP, 1400 px/s (an edge leaving frame as the camera pulls back is
// peripheral; a post skimmed past the lens is not, and 1400 still forbids that).
const SWEEP_W = 900 / 1400
// An object counts in full once it is 150 px inside the frame and fades out toward the edge: it is
// peripheral there, and a point stepping in at full weight would read as a jolt that is not on screen.
const EDGE = 150
const edgeW = (q2) => (q2 ? clamp01(Math.min(q2[0], W - q2[0], q2[1], H - q2[1]) / EDGE) : 0)
function imageStep(c0, c1) {
  world.pose(toCam(c0))
  const depth = world.project(...c0.at)?.[2] ?? 10
  const pts = GRID.map(([x, y]) => world.unproject(x, y, depth))
  const was = [...GRID, ...OBJ_REST.map((o) => world.project(...o))]
  const all = [...pts, ...OBJ_REST]
  world.pose(toCam(c1))
  let most = 0
  all.forEach((w, i) => {
    const a = was[i]
    if (!a || a[0] < 0 || a[0] > W || a[1] < 0 || a[1] > H) return
    const q2 = world.project(...w)
    if (q2) most = Math.max(most, Math.hypot(q2[0] - a[0], q2[1] - a[1]) * (i < GRID.length ? 1 : SWEEP_W * edgeW(a)))
  })
  return most
}
// The steps are smoothed into an envelope (a moving max, then a moving mean, over 1/6 of the path)
// before they are summed: the measure is a max over points, and when the point that dominates it leaves
// the frame the raw step drops at once, so timing on it would let the camera lurch forward (measured
// round two: 142 -> 385 px/s in three frames).
function arcTable(at) {
  const N = 480
  const w = 40
  const raw = []
  let prev = at(0)
  for (let i = 1; i <= N; i += 1) {
    const c = at(i / N)
    raw.push(imageStep(prev, c))
    prev = c
  }
  const win = (arr, i, f) => f(...arr.slice(Math.max(0, i - w), Math.min(arr.length, i + w + 1)))
  const hi = raw.map((_, i) => win(raw, i, Math.max))
  const env = hi.map((_, i) => win(hi, i, (...v) => v.reduce((x, y) => x + y, 0) / v.length))
  const acc = [0]
  env.forEach((d, i) => acc.push(acc[i] + d))
  return { acc, L: acc[N], N }
}
/** The path parameter k at which fraction a of the move's image travel is done. */
function kAtArc(tab, a) {
  if (!(tab.L > 0)) return clamp01(a)
  const want = clamp01(a) * tab.L
  let lo = 0
  let hi = tab.N
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1
    if (tab.acc[mid] < want) lo = mid
    else hi = mid
  }
  const seg = tab.acc[hi] - tab.acc[lo]
  return (lo + (seg > 0 ? (want - tab.acc[lo]) / seg : 0)) / tab.N
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
  decide: ['Only decisions reach you.'],
  racks: ['Landed is not live<br>until the running bytes match.'],
  // FILM only.
  gate: ['One land at a time.<br>A dangerous call never runs.'],
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
}

// ------------------------------------------------------------------------------------ the edits
// Round two's pacing (operator, 2026-09-25: "everything moves and jars so fast I don't feel oriented
// nor I can read anything in time"), gated by scripts/hero-film-pacing.py rather than by eye:
//   - every flight is a multi-second move whose PICTURE speed follows smootherstep (image travel
//     tabulated along an orbit path, so no frame outruns the bound and nothing starts or stops dead);
//   - every line lands while the camera is calm, stands still for its reading time BEFORE the story
//     moves under it, and stays until that story is done; type never moves while the camera is fast;
//   - fewer beats: the loop has three scenes, not five (README § Round 2).
// An edit holds `cam` (a pose; the FILM creeps toward `drift` over the hold) or is a flight `fly` from
// the edit before it to the edit after it. Story time and type are keyed on film time, per cut.
const LOOP = [
  { from: 0, to: 5.0, cam: 'poster', poster: true },
  { from: 5.0, to: 8.4, fly: { hop: 0.3 }, blur: true },
  { from: 8.4, to: 28.65, cam: 'window', chip: ['peer'] },
  // After the peer's commit: up off the window, over its line and the gate, down origin/main.
  { from: 28.65, to: 33.05, fly: { hop: 0.9, viaAt: [0, 4, 0] }, blur: true },
  { from: 33.05, to: 40.0, cam: 'racks', chip: ['verified', 'deploy'] },
  // REKEY: this flight's background is two levels off (invisible), so every pixel of the poster that
  // follows differs from the frame before it and the encoder re-sends the poster whole (sister repo).
  { from: 40.0, to: 44.6, fly: { hop: 0.6 }, blur: true, rekey: true },
  { from: 44.6, to: 45.9, cam: 'poster', poster: true },
]
// Story keys [film t, story s]: flat while a line is read; moving only on calm frames under a standing
// line, or inside a flight once the camera is under way (the card and the scrollback go as it leaves
// the poster; the peer's commit crosses the gate as the camera follows it; the peer folds its pane as
// the camera climbs home). Generated by tools/hero-film/schedule.py; README § Round 2 has the table.
const LOOP_STORY = [
  [0, S.start], [5.41, S.start], [6.31, S.clear], [11.3, S.clear], [11.45, 0],
  [14.75, 3.3], [19.95, 3.3], [21.45, S.card[1]], [29.18, S.card[1]], [31.29, S.stale[1]],
  [36.85, S.stale[1]], [38.9, S.lit[1]], [40.55, S.lit[1]], [44.05, S.END], [45.9, S.END],
]
const LOOP_TYPE = [
  { key: 'thought', out: [5.0, 5.44] },
  { key: 'split', in: [7.8, 8.5], out: [16.15, 16.75] },
  { key: 'decide', in: [16.75, 17.45], out: [28.65, 29.25] },
  { key: 'racks', in: [32.48, 33.15], out: [40.0, 40.6] },
  { key: 'thought', in: [43.9, 44.7] },
]
// The FILM: the same scenes and the gate between the window and the racks; the camera never holds
// still, it creeps through each shot (well under CALM) and flies between them.
const FILM = [
  { from: 0, to: 5.0, cam: 'poster', drift: 'posterIn', poster: true },
  { from: 5.0, to: 8.4, fly: { hop: 0.3 } },
  { from: 8.4, to: 28.65, cam: 'window', drift: 'windowB', chip: ['peer'] },
  { from: 28.65, to: 33.25, fly: { hop: 0.5, rise: 0.25 } },
  { from: 33.25, to: 41.85, cam: 'gate', drift: 'gateB', chip: ['force', 'denied', 'accounts'] },
  { from: 41.85, to: 46.05, fly: { hop: 0.3 } },
  { from: 46.05, to: 53.0, cam: 'racks', drift: 'racksB', chip: ['verified', 'deploy'] },
  { from: 53.0, to: 58.0, fly: { hop: 0.6 } },
  { from: 58.0, to: 63.5, cam: 'posterOut', drift: 'poster', poster: true },
]
const FILM_STORY = [
  [0, S.start], [5.41, S.start], [6.31, S.clear], [11.3, S.clear], [11.45, 0],
  [14.75, 3.3], [19.95, 3.3], [21.45, S.card[1]], [29.2, S.card[1]], [32.7, 4.9],
  [37.35, 4.9], [41.75, S.stale[0]], [42.35, S.stale[0]], [45.55, S.stale[1]], [49.85, S.stale[1]],
  [51.9, S.lit[1]], [53.6, S.lit[1]], [57.4, S.END], [63.5, S.END],
]
const FILM_TYPE = [
  { key: 'thought', out: [5.0, 5.44] },
  { key: 'split', in: [7.8, 8.5], out: [16.15, 16.75] },
  { key: 'decide', in: [16.75, 17.45], out: [28.65, 29.25] },
  { key: 'gate', in: [32.65, 33.35], out: [41.85, 42.35] },
  { key: 'racks', in: [45.5, 46.15], out: [53.0, 53.6] },
  { key: 'thought', in: [57.3, 58.1] },
]
const EDITS = CUT === 'film' ? FILM : LOOP
const STORY = CUT === 'film' ? FILM_STORY : LOOP_STORY
const TYPE = CUT === 'film' ? FILM_TYPE : LOOP_TYPE
// Chips that leave with their scene's first line rather than with the camera.
const CHIP_OUT = { peer: TYPE.find((x) => x.key === 'split').out }
const DURATION = EDITS[EDITS.length - 1].to
// A 360-degree shutter at 60 fps: round two's moves are slow enough that 1/60 s of blur is ~14 px at
// their peak, which reads as smooth motion rather than smear, and it cost 9 % fewer WebP bytes than
// 1/120 s (measured on one second of the longest flight). 8 sub-frames so the longer shutter never
// strobes.
const SHUTTER = Number(q.get('shutter') ?? 1 / 60)
const SUBS = Number(q.get('subs') ?? 8)

// ------------------------------------------------------------------------------------ one frame
let world = null
function editAt(t) {
  return EDITS.find((x) => t >= x.from && t < x.to) ?? EDITS[EDITS.length - 1]
}
function storyAt(t) {
  const i = STORY.findIndex(([t1], j) => j > 0 && t < t1)
  if (i < 0) return STORY[STORY.length - 1][1]
  const [t0, s0] = STORY[i - 1]
  const [t1, s1] = STORY[i]
  return lerp(s0, s1, p(t, t0, t1))
}
// Each moving edit's path and its image-travel table, built once the world exists. A flight runs from
// where the shot before it ended to where the shot after it begins; in the FILM it leaves and joins
// each shot's creep at that creep's own image speed (quintic Hermite), so the camera never jolts.
function prepMoves() {
  OBJ_REST = objectPoints({ card: cardAt(S.END) })
  EDITS.forEach((ed, i) => {
    if (ed.fly) {
      const prev = EDITS[i - 1]
      const next = EDITS[i + 1]
      ed._a = POSES[prev.drift ?? prev.cam]
      ed._b = POSES[next.cam]
      ed._tab = arcTable((k) => pathAt(ed._a, ed._b, k, ed.fly))
    } else if (ed.drift) {
      ed._tab = arcTable((k) => pathAt(POSES[ed.cam], POSES[ed.drift], k))
      ed._v = ed._tab.L / (ed.to - ed.from) // image px per second
    }
  })
  EDITS.forEach((ed, i) => {
    if (!ed.fly) return
    const T0 = ed.to - ed.from
    const per = ed._tab.L > 0 ? T0 / ed._tab.L : 0
    ed._m0 = (EDITS[i - 1]._v ?? 0) * per
    ed._m1 = (EDITS[i + 1]._v ?? 0) * per
  })
}
function camAt(ed, t) {
  if (ed.fly) return pathAt(ed._a, ed._b, kAtArc(ed._tab, hermite5(p(t, ed.from, ed.to), ed._m0, ed._m1)), ed.fly)
  if (ed.drift) return pathAt(POSES[ed.cam], POSES[ed.drift], kAtArc(ed._tab, p(t, ed.from, ed.to)))
  return POSES[ed.cam]
}
const REST = landState(S.start)
// Ambient commits: while the poster holds, three commits crawl toward the gate, so the poster reads as
// a running system and not a still (critique round two, finding 9). tau is time from the seam, so
// their positions agree on both sides of it; they fade in and out inside the flights either side.
const AMBIENT = [{ n: 4, u0: 0.45 }, { n: 9, u0: 0.35 }, { n: 3, u0: 0.55 }]
function ambientAt(t) {
  const tau = t < DURATION / 2 ? t : t - DURATION
  const first = EDITS[0].to
  const last = EDITS[EDITS.length - 1].from - DURATION
  const reach = [last - 0.5, first + 0.6]
  if (tau < reach[0] || tau > reach[1]) return null
  const a = e(tau, reach[0], reach[0] + 0.5, ease.travel) * (1 - e(tau, reach[1] - 0.5, reach[1], ease.travel))
  return AMBIENT.map((m) => ({ on: 'line', n: m.n, u: m.u0 + 0.05 * tau, a }))
}
function applyWorld(t) {
  const ed = editAt(t)
  const s = storyAt(t)
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
/** Kinetic type: words arrive (k 0 -> 1) rising into place in turn, and the line leaves whole. */
function kin(d, k, mode) {
  const ws = d._words
  const n = ws.length
  const stag = 0.16
  show(d, k > 0.001 ? 1 : 0)
  ws.forEach((w, i) => {
    const local = clamp01(k * (1 + stag * (n - 1)) - stag * i)
    if (mode === 'out') {
      // A line leaves whole: word by word, it left fragments that read as other sentences.
      const u = ease.smoother(1 - clamp01(k))
      w.style.opacity = (1 - u).toFixed(3)
      w.style.transform = `translate(${(-40 * u).toFixed(1)}px, 0)`
    } else {
      // Words rise into place on smootherstep: no word lands with a jolt.
      const u = ease.smoother(local)
      w.style.opacity = ease.smoother(clamp01(local * 1.4)).toFixed(3)
      w.style.transform = `translate(0, ${(26 * (1 - u)).toFixed(1)}px)`
    }
  })
}
function typeAt(t, st) {
  hideAll()
  show(mark)
  const ed = editAt(t)
  document.documentElement.style.setProperty('--bg', ed.rekey ? T.bgRekey : T.bg)
  let posterK = 0
  for (const x of TYPE) {
    const on = x.in ? x.in[0] : -Infinity
    const off = x.out ? x.out[1] : Infinity
    if (t < on || t >= off) continue
    let k
    let mode
    if (x.out && t >= x.out[0]) [k, mode] = [1 - p(t, x.out[0], x.out[1]), 'out']
    else [k, mode] = [x.in ? p(t, x.in[0], x.in[1]) : 1, 'in']
    if (k <= 0.001) continue
    if (x.key === 'thought') {
      THOUGHT.forEach((d) => kin(d, k, mode))
      posterK = Math.max(posterK, k)
    } else kin(lines[x.key], k, mode)
  }
  show(scrim, 1 - posterK)
  show(side, posterK)
  // Chips, in the edit that names them; across the first 0.6 s of the flight that follows they fade out
  // with the caption instead of cutting (critique round 3, m2).
  const i = EDITS.indexOf(ed)
  const trail = ed.fly && EDITS[i - 1]?.chip ? 1 - ease.smoother(p(t, ed.from, ed.from + 0.6)) : 1
  const want = new Set((ed.fly ? EDITS[i - 1]?.chip : ed.chip) ?? [])
  const s = st.s
  const S0 = world.stretches.find((x) => x.k === 0)
  const out = (k) => trail * (CHIP_OUT[k] ? 1 - p(t, CHIP_OUT[k][0], CHIP_OUT[k][1]) : 1)
  if (want.has('peer')) {
    const [fx, , fz] = hl(HW / 4, 0, 0.15)
    chipAt(chips.peer, fx, LIFT, fz, clamp01(st.peerLine * 2.2) * st.peerLineA * out('peer'), -200, 18)
  }
  if (want.has('force') && st.force) {
    const pt = world.pillPoint(S0, st.force)
    chipAt(chips.force, pt.x, 0.4, pt.z, st.force.a * out('force'), 26, -86)
    chips.force.style.color = st.force.red ? T.red : T.ink
    chips.force.style.borderColor = st.force.red ? T.red : T.faint
  }
  if (want.has('denied') && st.wall > 0.01) chipAt(chips.denied, S0.wallAt.x, 1.55, S0.wallAt.z, st.wallA * e(s, S.force.red, S.force.red + 0.15) * out('denied'), -10, -80)
  if (want.has('accounts')) {
    // Each account named once, in its own colour, on one of its lines.
    ;[6, 8, 3, 4].forEach((n, a) => {
      const pt = S0.lines[n].curve.getPointAt(0.3)
      chipAt(chips.acct[a], pt.x, 0, pt.z, out('accounts'), -40, -20)
    })
  }
  if (want.has('verified')) chipAt(chips.verified, 0, 0, RACK_Z + 4.2, e(s, S.verified, S.verified + 0.2) * out('verified'), -560, -84)
  if (want.has('deploy')) chipAt(chips.deploy, RACK_X[2], 0, RACK_Z + 1.5, e(s, S.deploy, S.deploy + 0.2) * out('deploy'), 40, -46)
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
    world.render(subs, { seed: Math.round(t * 60) })
  } else {
    applyWorld(t)
    world.render(null, { seed: Math.round(t * 60) })
  }
  const { st } = applyWorld(t)
  typeAt(t, st)
}

// ------------------------------------------------------------------------------------ the pacing probe
// scripts/hero-film-pacing.py gates the pacing on these numbers rather than on an eye: how fast the
// picture moves (image flow at the subject's depth, px per frame at 1920 wide, over a 3 x 3 grid), how
// fast the camera turns and travels, what the story clock does, and how visible and how still every
// piece of type is. Nothing is rendered: each frame is posed and laid out, then read back.
const UNITS = [
  ['thought', THOUGHT],
  ...Object.entries(lines).map(([k, d]) => [`line:${k}`, [d]]),
  ...Object.entries(chips).flatMap(([k, d]) => (Array.isArray(d) ? d.map((x, a) => [`chip:${k}${a}`, [x]]) : [[`chip:${k}`, [d]]])),
]
function textOf(ds) {
  let code = ''
  let all = ''
  for (const d of ds) {
    all += ` ${d.textContent}`
    if (d.classList.contains('mono')) code += ` ${d.textContent}`
    else d.querySelectorAll('.mono').forEach((m) => { code += ` ${m.textContent}` })
  }
  let prose = all
  for (const c of code.trim().split(/\s+/)) prose = prose.replace(c, ' ')
  return { prose: prose.trim().replace(/\s+/g, ' '), code: code.trim() }
}
function unitState(ds) {
  let vis = 1
  let move = 0
  for (const d of ds) {
    const o = d.style.visibility === 'visible' ? Number(d.style.opacity || 1) : 0
    vis = Math.min(vis, o)
    for (const w of d._words ?? []) {
      vis = Math.min(vis, o * Number(w.style.opacity || 1))
      const m = /translate\(([-\d.]+)px, ([-\d.]+)px\)/.exec(w.style.transform)
      if (m) move = Math.max(move, Math.hypot(Number(m[1]), Number(m[2])))
    }
  }
  return [Number(vis.toFixed(3)), Number(move.toFixed(1)), Number.parseFloat(ds[0].style.left) || 0, Number.parseFloat(ds[0].style.top) || 0]
}
// Named objects the camera must not sweep past (the grid above only sees the subject's depth): the
// gate's posts, the originator's window, each rack, each fleet window, and the card while it shows.
function objectPoints(st) {
  const pts = []
  for (const sx of [-1.5, 1.5]) for (const y of [0, 4.2]) pts.push([sx, y, 0])
  for (const lx of [-HW / 2, HW / 2]) for (const ly of [LIFT, LIFT + HH]) pts.push(hl(lx, ly, 0))
  for (const x of RACK_X) for (const dx of [-1.7, 1.7]) for (const y of [0, 5]) pts.push([x + dx, y, RACK_Z])
  for (const f of FLEET) for (const y of [LIFT, LIFT + FH]) pts.push([f.x, y, f.z])
  if (st.card && st.card.a > 0.01) {
    const c = st.card
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) pts.push([c.x + sx * RX * 1.05 * c.scale, c.y + sy * 0.615 * c.scale, c.z + sx * RZ * 1.05 * c.scale])
  }
  return pts
}
function probe(t, dt) {
  const c0 = camAt(editAt(t), t)
  world.pose(toCam(c0))
  const depth = world.project(...c0.at)?.[2] ?? 10
  const pts = GRID.map(([x, y]) => world.unproject(x, y, depth))
  const m = world.cam.matrixWorld.elements
  const fwd = [-m[8], -m[9], -m[10]]
  const t1 = (((t + dt) % DURATION) + DURATION) % DURATION
  world.pose(toCam(camAt(editAt(t1), t1)))
  const flow = pts.map((w, i) => {
    const q = world.project(...w)
    return q ? Math.hypot(q[0] - GRID[i][0], q[1] - GRID[i][1]) : 1e4
  })
  const { ed, s, st } = applyWorld(t)
  typeAt(t, st)
  // Object sweep: each named point on screen now, where the next frame's camera puts it.
  const obj = objectPoints(st)
  const near = Math.min(...obj.map((o) => Math.hypot(o[0] - c0.p[0], o[1] - c0.p[1], o[2] - c0.p[2])))
  world.pose(toCam(c0))
  const on = obj.map((o) => world.project(...o)).map((q2) => (q2 && q2[0] > 0 && q2[0] < W && q2[1] > 0 && q2[1] < H ? q2 : null))
  world.pose(toCam(camAt(editAt(t1), t1)))
  let sweep = 0
  obj.forEach((o, i) => {
    if (!on[i]) return
    const q2 = world.project(...o)
    sweep = Math.max(sweep, (q2 ? Math.hypot(q2[0] - on[i][0], q2[1] - on[i][1]) : 1e4) * edgeW(on[i]))
  })
  world.pose(toCam(c0))
  let card = null
  if (st.card) {
    // Its centre on screen and its width there: the card is type only while it is big enough to read.
    const c = st.card
    const hw = 1.05 * c.scale
    const l = world.project(c.x - RX * hw, c.y, c.z - RZ * hw)
    const r = world.project(c.x + RX * hw, c.y, c.z + RZ * hw)
    const mid = world.project(c.x, c.y, c.z)
    card = { a: Number(c.a.toFixed(3)), at: mid ? mid.slice(0, 2).map((v) => Number(v.toFixed(1))) : null, w: l && r ? Number(Math.hypot(r[0] - l[0], r[1] - l[1]).toFixed(1)) : 0 }
  }
  return {
    t: Number(t.toFixed(4)), s: Number(s.toFixed(5)), edit: EDITS.indexOf(ed), fly: !!ed.fly,
    p: c0.p.map((v) => Number(v.toFixed(4))), fwd: fwd.map((v) => Number(v.toFixed(6))), F: Number(c0.F.toFixed(2)),
    flow: flow.map((v) => Number(v.toFixed(2))), depth: Number(depth.toFixed(2)), sweep: Number(sweep.toFixed(2)), near: Number(near.toFixed(2)),
    units: Object.fromEntries(UNITS.map(([k, ds]) => [k, unitState(ds)])), card,
  }
}
// While composing: the image travel (px at 1920) of a move between two poses, for a flight spec.
window.__moveL = (a, b, spec = {}) => arcTable((k) => pathAt(POSES[a], POSES[b], k, spec)).L
window.__pacing = (fps = 60) => {
  const frames = []
  for (let f = 0; f < Math.round(DURATION * fps); f += 1) frames.push(probe(f / fps, 1 / fps))
  const texts = Object.fromEntries(UNITS.map(([k, ds]) => [k, textOf(ds)]))
  texts.card = { prose: CARD_TEXT, code: '' }
  return { cut: CUT, theme: THEME, duration: DURATION, fps, edits: EDITS.map((x, i) => ({ from: x.from, to: x.to, fly: x.fly ? [EDITS[i - 1].drift ?? EDITS[i - 1].cam, EDITS[i + 1].cam] : null, cam: x.cam ?? null, line: null, poster: !!x.poster })), texts, frames }
}

window.__duration = DURATION
// What the encoder needs to know: where the camera flies (hero-film-encode-loop.py stores those frames
// lossy; every frame of both cuts is 60 fps since round two) and which holds are the poster (their
// first frame is stored near-lossless: frame 0 is the most-seen frame, and the seam is exact only if
// the poster decodes the same both times it is shown).
window.__meta = {
  cut: CUT,
  duration: DURATION,
  flights: EDITS.filter((x) => x.fly).map((x) => [x.from, x.to]),
  nearLossless: EDITS.filter((x) => x.poster && x.cam).map((x) => [x.from, x.to]),
}
const seekAny = (t) => seek(((t % DURATION) + DURATION) % DURATION)
Promise.all(['400 26px "Geist"', '500 26px "Geist"', '600 26px "Geist"', '400 26px "Geist Mono"', '500 26px "Geist Mono"', '600 26px "Geist Mono"'].map((f) => document.fonts.load(f))).then(() => document.fonts.ready).then(() => {
  // Grain moves every pixel of every frame, so it is the FILM's only: in the loop's animated WebP a still
  // frame is nearly free, and grain would make every hold cost what a flight costs.
  world = buildWorld(T, { width: W, height: H, grain: CUT === 'film' ? Number(q.get('grain') ?? 2.2) : 0 })
  prepMoves()
  stage.append(world.renderer.domElement)
  stage.append(layer)
  window.__seek = seekAny
  window.__ready = true
  window.__seek(Number(q.get('t') ?? 0))
})

export { FLEET }
