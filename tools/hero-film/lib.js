// tools/hero-film/lib.js: the clock, the easings and the theme tokens every scene uses.
//
// Adapted from agent-context-sync film/lib.js (round 3, approved 2026-09-24). The film is a pure
// function of time: nothing here keeps state between calls to seek(t), so any frame can be rendered
// in any order and renders the same pixels every time.

export const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x)
export const lerp = (a, b, k) => a + (b - a) * k

// Named easings. Arrivals settle (expo out), exits leave (expo in), moves between states travel
// (cubic in-out), the camera glides (quint in-out), anything metered walks at constant speed.
export const ease = {
  settle: (x) => (x >= 1 ? 1 : 1 - 2 ** (-10 * x)),
  leave: (x) => (x <= 0 ? 0 : 2 ** (10 * x - 10)),
  travel: (x) => (x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2),
  glide: (x) => (x < 0.5 ? 16 * x ** 5 : 1 - (-2 * x + 2) ** 5 / 2),
  soft: (x) => 0.5 - Math.cos(Math.PI * clamp01(x)) / 2,
  walk: (x) => x,
  // Smootherstep: leaves and arrives with zero speed AND zero acceleration, so no start or stop jolts.
  smoother: (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * x * (x * (6 * x - 15) + 10)),
}

/**
 * Quintic Hermite progress over u in 0..1: from 0 to 1 with speed m0 at the start and m1 at the end
 * (in units of the average speed) and zero acceleration at both ends. m0 = m1 = 0 is smootherstep.
 * The film's flights use it to leave and join a drifting camera without a jolt.
 */
export function hermite5(u, m0 = 0, m1 = 0) {
  const x = clamp01(u)
  const x3 = x * x * x
  const x4 = x3 * x
  const x5 = x4 * x
  return m0 * (x - 6 * x3 + 8 * x4 - 3 * x5) + m1 * (-4 * x3 + 7 * x4 - 3 * x5) + (10 * x3 - 15 * x4 + 6 * x5)
}

/** Progress of t through [a, b], clamped to 0..1. */
export const p = (t, a, b) => clamp01((t - a) / (b - a))
/** Eased progress of t through [a, b]. */
export const e = (t, a, b, fn = ease.settle) => fn(p(t, a, b))

// Colour means one thing each: amber = work in flight, green = verified or landed, red = refused.
// The four account hues are for lane lines and ①–④ badges only. Grades match GitHub's page colours.
export const THEMES = {
  dark: {
    bg: '#0d1117', ink: '#e6edf3', muted: '#8b949e', faint: '#30363d', dim: '#484f58',
    amber: '#f0a33a', green: '#3fb950', greenInk: '#56d364', red: '#ff7b72', redFill: '#3d1519',
    // Four cool hues at matched lightness, well away from refused-red (critique round two, finding 5).
    acct: ['#39c5cf', '#58a6ff', '#8b8dff', '#c297ff'],
    clawd: '#d77757',
    // A kitty window: bezel, title bar, pane body, and Claude Code's own row tints.
    bezel: '#30363d', title: '#1c2128', titleInk: '#8b949e', pane: '#161b22', paneInk: '#e6edf3', paneMuted: '#8b949e',
    promptRow: '#262c36', greek: '#30363d', greekHi: '#484f58', divider: '#8b949e',
    // The floor and its light.
    floor: '#0d1117', grid: '#161b22', reflect: 0.2, glowA: 0.22, shadow: '#010409', shadowA: 0.55,
    // Racks and cards.
    rack: '#161b22', rackEdge: '#30363d', rackDim: '#484f58', card: '#1c2128', cardEdge: '#6e7681',
    liveRow: '#12261a', amberRow: '#2d2111', amberText: '#f0a33a',
    gate: '#8b949e', gateArm: '#e6edf3',
    bgRekey: '#0d1119',
  },
  light: {
    bg: '#ffffff', ink: '#1f2328', muted: '#59636e', faint: '#d0d7de', dim: '#afb8c1',
    amber: '#c86a00', green: '#1a7f37', greenInk: '#1a7f37', red: '#cf222e', redFill: '#ffebe9',
    acct: ['#0092b8', '#0969da', '#4b4fd6', '#8250df'],
    clawd: '#d77757',
    // Surfaces two steps darker than GitHub's canvas, so a pane survives 838 px on white (sister repo).
    bezel: '#6e7781', title: '#d8dee4', titleInk: '#424a53', pane: '#eef1f4', paneInk: '#1f2328', paneMuted: '#59636e',
    promptRow: '#dde3e9', greek: '#c4ccd4', greekHi: '#8c959f', divider: '#59636e',
    // Two steps darker than GitHub's canvas where the world has surfaces (sister repo, round 3).
    floor: '#ffffff', grid: '#e6eaef', reflect: 0.14, glowA: 0.16, shadow: '#1f2328', shadowA: 0.24,
    rack: '#eef1f4', rackEdge: '#6e7781', rackDim: '#8c959f', card: '#ffffff', cardEdge: '#6e7781',
    liveRow: '#dafbe1', amberRow: '#fff1dc', amberText: '#9a4a00',
    gate: '#59636e', gateArm: '#1f2328',
    bgRekey: '#fffffd',
  },
}

/** Deterministic PRNG (mulberry32), so every "random" layout is the same on every frame and run. */
export function rng(seed) {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
