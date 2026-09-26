// tools/hero-film/world.js: one world, in three.js. The floor is a git graph in 3D.
//
// Kitty windows running Claude Code stand in a fan around a gate, each at the head of its own
// branch line, drawn in its account's colour. Every line bends into the gate, the land-lock, and
// leaves it as one green trunk, origin/main, which runs on past ~/.claude: three racks, hooks/
// commands/ skills/, whose real files light up when the running bytes match.
//
// The world is PERIODIC in depth (the sister repo's device, agent-context-sync film/world.js): it is
// cut into stretches DZ long, one land each, and every stretch holds the same objects in the same
// places. A land happens in one stretch; the camera then moves on to the next, so nothing is ever
// undone and the loop's last frame is its first moved one stretch down the floor.
//
// Nothing here keeps time. film.js computes every state from the clock and calls update().

import * as THREE from 'three'
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js'
import { RACKS, canvas, drawCard, drawFloorText, drawRack, drawSign, drawWindow } from './panes.js'
import { clamp01, rng } from './lib.js'
import { LAYER_FLOOR, LOOKS, environment, floorMaterial, initAreaLights, pipeline } from './look.js'

// Round 3: every canvas is drawn at TEX times round two's size, so a pane's text stays sharp in a 4K
// frame (the window shot puts the originator's window ~2,700 px wide).
export const TEX = 2

// --------------------------------------------------------------------------------- the layout
export const DZ = 56 // one stretch, one land
export const gateZ = (k) => -k * DZ
export const RACK_Z = -21 // the racks, after the gate
export const RACK_X = [-4.3, 0, 4.3]
export const RACK_W = 3.4
export const RACK_H = 5.0
export const STRETCHES = [0] // the story is cyclic (film.js), so one stretch is the whole world
export const FW = 3.2 // a fleet window
export const FH = 2.0
export const HW = 4.6 // the originator's window, which splits in two
export const HH = 2.5
export const LIFT = 0.28 // windows stand this far off the floor
// A fleet window turns only this fraction of its angle round the gate: turned fully, the flanks showed
// their backs to every camera as blank slabs (critique round two, finding 10).
const FACE = 0.15
export const HEAD_Z = -1.6 // origin/main's newest commit, just past the gate
export const HIST_DZ = 0.9 // spacing of the commits on origin/main
const HIST_N = 64

// The fleet: two rings round the gate, angles interleaved so every outer line runs between two inner
// windows. Angle is measured from +z (toward the camera) toward +x. acct: 0..3, left to right.
const polar = (R, deg) => [R * Math.sin((deg * Math.PI) / 180), R * Math.cos((deg * Math.PI) / 180)]
const acctOf = (deg) => (deg < -33 ? 0 : deg < 0 ? 1 : deg < 33 ? 2 : 3)
// Real worktree branches from this repo (git worktree list, 2026-09-24), one per window.
const BRANCHES = [
  'fix/stop-hook-latency', 'feat/wake-on-ping', 'fix/mailbox-writer-key', 'docs/entrypoint-consolidation',
  'fix/sigterm-forensics', 'feat/mcp-config-ssot', 'fix/accounts-board-starvation', 'feat/memory-realpath',
  'fix/notify-headless-chime', 'feat/permission-pending-beacon', 'fix/kitty-rearm-operator-ruled', 'fix/untracked-dodref',
]
// And one real command each, the only legible row a fleet window carries below its header.
const COMMANDS = [
  '/ship', 'bats tests/stop-hook-latency.bats', 'git rebase origin/main', '/wrap',
  'scripts/wrap-ledger.sh --machine', 'cc-backlog list --blocked', 'claude-accounts --readout', '/handoff',
  'bats tests/deploy-parity.bats', 'git ls-tree origin/main -- hooks/', 'cc-custody list', '/research',
]
export const FLEET = []
{
  const inner = [-66, -41, -16, 16, 41, 66]
  const outer = [-78, -53, -28, 53, 78] // +28 is the originator's
  inner.forEach((d) => FLEET.push({ R: 13, deg: d }))
  outer.forEach((d) => FLEET.push({ R: 22, deg: d }))
  FLEET.forEach((o, n) => {
    const [x, z] = polar(o.R, o.deg)
    Object.assign(o, { x, z, acct: acctOf(o.deg), branch: BRANCHES[n], cmd: COMMANDS[n], seed: 31 + n * 7 })
  })
}
// The originator: the session that fires the peer, on the outer ring at +28 degrees.
export const HERO = (() => {
  const deg = 28
  const [x, z] = polar(22, deg)
  return { R: 22, deg, x, z, acct: 0, branch: 'docs/readme-opus55', peerAcct: 2, peerBranch: 'feat/readme-hero-film' }
})()
// A window's floor point for its line: left half (the originator) and right half (the peer).
const rot = (deg) => (deg * Math.PI) / 180
export function heroFoot(half) {
  const a = rot(HERO.deg)
  const dx = (half === 0 ? -HW / 4 : HW / 4)
  return [HERO.x + Math.cos(a) * dx, HERO.z - Math.sin(a) * dx]
}
// Where the card rises from: a window on the inner ring.
export const CARD_FROM = 2

// --------------------------------------------------------------------------------- lines
// A branch line: from a window's foot, bending into the gate's mouth along -z (a git merge curve).
function branchCurve(x0, z0, gz) {
  const P0 = new THREE.Vector3(x0, 0, z0 - 0.2)
  const P3 = new THREE.Vector3(0, 0, gz + 1.2)
  const P1 = new THREE.Vector3(x0 * 0.72, 0, gz + (z0 - gz) * 0.55)
  const P2 = new THREE.Vector3(0, 0, gz + Math.min(7, (z0 - gz) * 0.45))
  return new THREE.CubicBezierCurve3(P0, P1, P2, P3)
}
/** A flat ribbon along a curve, on the floor. u runs 0..1 along it (for a line drawing itself). */
function ribbon(curve, width, n = 96) {
  const pos = new Float32Array((n + 1) * 2 * 3)
  const uv = new Float32Array((n + 1) * 2 * 2)
  const idx = []
  const pt = new THREE.Vector3()
  const tg = new THREE.Vector3()
  for (let i = 0; i <= n; i += 1) {
    const u = i / n
    curve.getPointAt(u, pt)
    curve.getTangentAt(u, tg)
    const nx = -tg.z
    const nz = tg.x
    const l = Math.hypot(nx, nz) || 1
    for (let s = 0; s < 2; s += 1) {
      const sg = s === 0 ? -1 : 1
      pos.set([pt.x + (sg * nx * width) / (2 * l), 0, pt.z + (sg * nz * width) / (2 * l)], (i * 2 + s) * 3)
      uv.set([u, s], (i * 2 + s) * 2)
    }
    if (i < n) idx.push(i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2)
  }
  const g = new THREE.BufferGeometry()
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3))
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2))
  g.setIndex(idx)
  return g
}
// A ribbon's material draws only u <= `draw` (a line growing from its window), in one colour.
// Round 3: `boost` lifts a line above the bloom threshold, so it emits light rather than being paint.
function lineMat(color, opacity = 1, additive = false, boost = 1) {
  return new THREE.ShaderMaterial({
    uniforms: { color: { value: new THREE.Color(color) }, opacity: { value: opacity }, draw: { value: 1 }, from: { value: 0 }, soft: { value: 0 }, boost: { value: boost }, fogColor: { value: new THREE.Color() }, fogNear: { value: 1 }, fogFar: { value: 2 } },
    vertexShader: 'varying vec2 vUv; varying float vDepth; void main() { vUv = uv; vec4 mv = modelViewMatrix * vec4(position, 1.0); vDepth = -mv.z; gl_Position = projectionMatrix * mv; }',
    fragmentShader: `uniform vec3 color; uniform float opacity; uniform float draw; uniform float from; uniform float soft; uniform float boost; uniform vec3 fogColor; uniform float fogNear; uniform float fogFar;
      varying vec2 vUv; varying float vDepth;
      void main() {
        if (vUv.x > draw || vUv.x < from) discard;
        float a = opacity;
        if (soft > 0.0) { float d = abs(vUv.y - 0.5) * 2.0; a *= pow(1.0 - d, 2.0); }
        float f = smoothstep(fogNear, fogFar, vDepth);
        gl_FragColor = vec4(mix(color * boost, fogColor, f), a);
        #include <colorspace_fragment>
      }`,
    transparent: true,
    depthWrite: false,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  })
}

// --------------------------------------------------------------------------------- building
export function buildWorld(T, { width = 1920, height = 1080, grain = 0 } = {}) {
  const dark = T.bg === '#0d1117'
  const L = LOOKS[dark ? 'dark' : 'light']
  // The page is laid out at 1920 x 1080 CSS px and photographed at the device pixel ratio (2 in round
  // 3: 3840 x 2160, the FILM's size and the loop's supersampled source).
  const dpr = window.devicePixelRatio || 1
  const renderer = new THREE.WebGLRenderer({ antialias: false, preserveDrawingBuffer: true, powerPreference: 'high-performance' })
  renderer.setPixelRatio(dpr)
  renderer.setSize(width, height)
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.NoToneMapping // look.js rolls highlights off itself, leaving the page colour exact
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFShadowMap
  const maxAniso = renderer.capabilities.getMaxAnisotropy()
  const scene = new THREE.Scene()
  const bg = new THREE.Color(T.bg)
  scene.background = bg
  scene.fog = new THREE.Fog(bg, 40, 150)
  scene.environment = environment(renderer)
  initAreaLights()
  const cam = new THREE.PerspectiveCamera(40, width / height, 0.05, 800)
  cam.rotation.order = 'YXZ'
  cam.layers.enable(LAYER_FLOOR)
  // Things lying on the floor: drawn in the main pass, never in the reflection (look.js).
  const onFloor = (...objs) => {
    for (const o of objs) o.traverse((m) => m.layers.set(LAYER_FLOOR))
    return objs[0]
  }

  const tex = (c) => {
    const t = new THREE.CanvasTexture(c)
    t.colorSpace = THREE.SRGBColorSpace
    t.anisotropy = maxAniso
    t.generateMipmaps = true
    t.minFilter = THREE.LinearMipmapLinearFilter
    return t
  }
  const lineMats = [] // every ShaderMaterial that needs the fog uniforms each frame
  const mkLine = (color, opacity, additive, boost = 1) => {
    const m = lineMat(color, opacity, additive, boost)
    lineMats.push(m)
    return m
  }

  // ---------------------------------------------------------------------- materials
  // A kitty window is a physical object: a dark anodised bezel with a clearcoat, the lit screen set in
  // it, and a sheet of glass whose reflections of the room slide across it as the camera moves.
  const bezelMat = new THREE.MeshPhysicalMaterial({ color: L.body, metalness: 0.6, roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.18, envMapIntensity: L.env })
  const glassMat = new THREE.MeshStandardMaterial({ color: 0x000000, metalness: 0, roughness: 0.06, envMapIntensity: L.glass, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false })
  const metalMat = new THREE.MeshPhysicalMaterial({ color: L.metalHi, metalness: 0.9, roughness: 0.28, clearcoat: 0.3, envMapIntensity: L.env * 1.2 })
  const darkMetal = new THREE.MeshPhysicalMaterial({ color: L.metal, metalness: 0.75, roughness: 0.4, envMapIntensity: L.env })
  const lampMat = (color, k = L.lineBoost) => new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(k), toneMapped: false })
  /** A panel standing on its bottom edge (or centred), facing +z: bezel body, screen, glass. */
  function panel(w, h, map, { depth = 0.08, rim = 0.05, radius = 0.06, centre = false, own = false } = {}) {
    const g = new THREE.Group()
    const y0 = centre ? 0 : h / 2
    const bm = own ? bezelMat.clone() : bezelMat
    const body = new THREE.Mesh(new RoundedBoxGeometry(w + 2 * rim, h + 2 * rim, depth, 4, radius).translate(0, y0, -depth / 2 + 0.004), bm)
    body.castShadow = true
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(w, h).translate(0, y0, 0.007), new THREE.MeshBasicMaterial({ map, transparent: true, color: new THREE.Color().setScalar(L.screen) }))
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(w, h).translate(0, y0, 0.011), own ? glassMat.clone() : glassMat)
    glass.renderOrder = 9
    g.add(body, screen, glass)
    return { g, body, screen, glass }
  }
  const addStanding = (obj) => {
    scene.add(obj)
    return obj
  }

  // A soft contact shadow under each standing thing (the key light's shadow falls well away from a
  // window that floats LIFT off the floor; this keeps it grounded).
  const blob = (() => {
    const c = canvas(256, 256)
    const g = c.getContext('2d')
    const gr = g.createRadialGradient(128, 128, 0, 128, 128, 128)
    gr.addColorStop(0, '#ffffff')
    gr.addColorStop(0.45, '#6a6a6a')
    gr.addColorStop(1, '#000000')
    g.fillStyle = gr
    g.fillRect(0, 0, 256, 256)
    return new THREE.CanvasTexture(c)
  })()
  const floorBlob = (w, d, color, opacity) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, d).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color, alphaMap: blob, transparent: true, opacity, depthWrite: false }))
    m.renderOrder = 1
    m.layers.set(LAYER_FLOOR)
    return m
  }

  // ---------------------------------------------------------------------- light
  // A cool key from high behind the fleet (rim-lights every window and throws its shadow toward the
  // lens), a sky/ground fill, a faint front rim, and each lit screen as an area light on the floor.
  scene.add(new THREE.HemisphereLight(L.hemi[0], L.hemi[1], L.hemi[2]))
  const key = new THREE.DirectionalLight(L.key[0], L.key[1])
  key.position.set(-22, 30, 20)
  key.target.position.set(2, 0, -2)
  key.castShadow = true
  Object.assign(key.shadow.camera, { left: -44, right: 44, top: 44, bottom: -44, near: 1, far: 120 })
  key.shadow.mapSize.set(4096, 4096)
  key.shadow.bias = -0.0004
  key.shadow.normalBias = 0.03
  key.shadow.radius = 4
  scene.add(key, key.target)
  const rimL = new THREE.DirectionalLight(L.rim[0], L.rim[1])
  rimL.position.set(18, 9, -30) // a cool edge from behind
  scene.add(rimL)
  const screenLight = (w, h, x, y, z, yaw, color = '#c9d6ff', k = 1) => {
    if (!L.screenLight) return null
    const l = new THREE.RectAreaLight(color, L.screenLight * k, w, h)
    l.position.set(x + Math.sin(yaw) * 0.05, y, z + Math.cos(yaw) * 0.05)
    l.lookAt(x + Math.sin(yaw) * 2, y, z + Math.cos(yaw) * 2)
    scene.add(l)
    return l
  }

  // ---------------------------------------------------------------------- the floor
  // Polished concrete with inlaid seams every 4 units (the old grid: it still reads a flight's speed),
  // reflecting everything standing on it, blurred (look.js).
  const floorMat = floorMaterial(L)
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(640, 960).rotateX(-Math.PI / 2), floorMat)
  floor.position.set(0, 0, -200)
  floor.receiveShadow = true
  floor.layers.set(LAYER_FLOOR)
  floor.renderOrder = -3
  scene.add(floor)
  // Dust in the air, lit: fixed in the world, so it parallaxes in a flight and is still in a hold.
  if (L.motes) {
    const R = rng(97)
    const pos = new Float32Array(L.motes * 3)
    for (let i = 0; i < L.motes; i += 1) pos.set([(R() - 0.5) * 70, 0.3 + R() ** 1.6 * 10, 32 - R() * 80], i * 3)
    const dot = (() => {
      const c = canvas(64, 64)
      const g = c.getContext('2d')
      const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32)
      gr.addColorStop(0, 'rgba(255,255,255,1)')
      gr.addColorStop(1, 'rgba(255,255,255,0)')
      g.fillStyle = gr
      g.fillRect(0, 0, 64, 64)
      return new THREE.CanvasTexture(c)
    })()
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    const motes = new THREE.Points(geo, new THREE.PointsMaterial({ size: 0.05, map: dot, color: '#9fb4d6', transparent: true, opacity: 0.35, depthWrite: false, blending: THREE.AdditiveBlending }))
    motes.layers.set(LAYER_FLOOR)
    scene.add(motes)
  }

  // ---------------------------------------------------------------------- the trunk
  // origin/main: one green line through every stretch, with its history as commit dots.
  const trunkZ0 = 1.2 // origin/main starts at the gate: before it there is no trunk, only branches
  const trunkZ1 = -DZ * 5
  const trunkCurve = new THREE.LineCurve3(new THREE.Vector3(0, 0, trunkZ0), new THREE.Vector3(0, 0, trunkZ1))
  const trunk = new THREE.Mesh(ribbon(trunkCurve, 0.24, 4), mkLine(T.green, 1, false, L.lineBoost))
  trunk.position.y = 0.012
  trunk.renderOrder = 3
  scene.add(trunk)
  const trunkGlow = new THREE.Mesh(ribbon(trunkCurve, 2.0, 4), mkLine(T.green, T.glowA * 0.9, dark))
  trunkGlow.material.uniforms.soft.value = 1
  trunkGlow.position.y = 0.008
  trunkGlow.renderOrder = 2
  scene.add(trunkGlow)
  onFloor(trunk, trunkGlow)
  const dotGeo = new THREE.CircleGeometry(0.13, 32).rotateX(-Math.PI / 2)
  const ringGeo = new THREE.RingGeometry(0.2, 0.3, 40).rotateX(-Math.PI / 2)

  // ---------------------------------------------------------------------- per stretch
  const fleetCanvases = FLEET.map((o) => {
    const c = canvas(1024 * TEX, 640 * TEX)
    drawWindow(c.getContext('2d'), T, 1024 * TEX, 640 * TEX, {
      title: `✳ ${o.branch}`,
      k: TEX,
      panes: [{
        font: 21 * TEX, acct: o.acct, sess: `claude-infrastructure (${(o.seed * 2654435761 >>> 0).toString(16).slice(0, 8)})`, greekSeed: o.seed,
        header: { version: 'v2.1.280', model: 'Opus 5.5 · Claude Max', cwd: `~/…/.worktrees/${o.branch}` },
        rows: [{ kind: 'user', text: o.cmd }, { kind: 'greek', lines: 2 }, { kind: 'greek', lines: 3 }, { kind: 'greek', lines: 1 }],
      }],
    })
    return tex(c)
  })
  const branchLabel = (text, color) => {
    const c = canvas(1024 * TEX, 96 * TEX)
    drawFloorText(c.getContext('2d'), 1024 * TEX, 96 * TEX, text, color)
    const t = tex(c)
    return t
  }
  const gateSign = (() => {
    const c = canvas(768 * TEX, 256 * TEX)
    drawSign(c.getContext('2d'), T, 768 * TEX, 256 * TEX)
    return tex(c)
  })()
  const floorWord = (text, color, h = 128) => {
    const c = canvas(1024 * TEX, h * TEX)
    drawFloorText(c.getContext('2d'), 1024 * TEX, h * TEX, text, color, { align: 'center', weight: 600 })
    return tex(c)
  }
  const mainWord = floorWord('origin/main', T.green)
  const claudeWord = floorWord('~/.claude', T.ink)

  const stretches = []
  for (const k of STRETCHES) {
    const gz = gateZ(k)
    const S = { k, gz, fleet: [], lines: [], pills: [] }
    // Fleet windows and their lines.
    FLEET.forEach((o, n) => {
      const { g, screen: face } = panel(FW, FH, fleetCanvases[n])
      g.position.set(o.x, LIFT, gz + o.z)
      g.rotation.y = rot(o.deg * FACE)
      addStanding(g)
      const sh = floorBlob(FW * 1.25, 1.2, T.shadow, T.shadowA * 0.7)
      sh.position.set(o.x, 0.003, gz + o.z - 0.1)
      sh.rotation.y = rot(o.deg * FACE)
      scene.add(sh)
      // The screen lights the floor in front of it, in its account's hue.
      screenLight(FW, FH, o.x, LIFT + FH / 2, gz + o.z, rot(o.deg * FACE), T.acct[o.acct], 0.8)
      const curve = branchCurve(o.x, o.z + gz, gz)
      const line = new THREE.Mesh(ribbon(curve, 0.15), mkLine(T.acct[o.acct], 1, false, L.lineBoost))
      line.position.y = 0.01
      line.renderOrder = 3
      const glow = new THREE.Mesh(ribbon(curve, 1.5), mkLine(T.acct[o.acct], T.glowA * 0.8, dark))
      glow.material.uniforms.soft.value = 1
      glow.position.y = 0.006
      glow.renderOrder = 2
      scene.add(line, glow)
      // The branch's name, painted along the line just ahead of the window.
      const lab = new THREE.Mesh(new THREE.PlaneGeometry(3.4, 0.32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ map: branchLabel(o.branch, T.acct[o.acct]), transparent: true, depthWrite: false, opacity: 0.7 }))
      const p0 = curve.getPointAt(0.1)
      const tg = curve.getTangentAt(0.1)
      lab.position.set(p0.x, 0.012, p0.z)
      lab.rotation.y = Math.atan2(-tg.x, -tg.z) + Math.PI / 2
      lab.translateX(0.35)
      lab.translateZ(-1.95)
      lab.renderOrder = 4
      scene.add(lab)
      onFloor(line, glow, lab)
      S.fleet.push({ o, g, face })
      S.lines.push({ curve, line, glow, acct: o.acct, n })
    })

    // The originator's window: two panes once it splits. One canvas per stretch, redrawn on change.
    const hc = canvas(2048 * TEX, 1114 * TEX)
    const ht = tex(hc)
    const { g: hero } = panel(HW, HH, ht, { depth: 0.1, rim: 0.06 })
    hero.position.set(HERO.x, LIFT, gz + HERO.z)
    hero.rotation.y = rot(HERO.deg)
    addStanding(hero)
    {
      const sh = floorBlob(HW * 1.2, 1.3, T.shadow, T.shadowA * 0.7)
      sh.position.set(HERO.x, 0.003, gz + HERO.z - 0.1)
      sh.rotation.y = rot(HERO.deg)
      scene.add(sh)
      screenLight(HW, HH, HERO.x, LIFT + HH / 2, gz + HERO.z, rot(HERO.deg), '#dfe6f2', 1.0)
    }
    // Its two lines: the originator's (left half) and the peer's (right half, drawn as it boots).
    const heroLines = [0, 1].map((half) => {
      const [fx, fz] = heroFoot(half)
      const curve = branchCurve(fx, fz + gz, gz)
      const acct = half === 0 ? HERO.acct : HERO.peerAcct
      const line = new THREE.Mesh(ribbon(curve, 0.17), mkLine(T.acct[acct], 1, false, L.lineBoost))
      line.position.y = 0.011
      line.renderOrder = 3
      const glow = new THREE.Mesh(ribbon(curve, 1.6), mkLine(T.acct[acct], T.glowA * 0.8, dark))
      glow.material.uniforms.soft.value = 1
      glow.position.y = 0.007
      glow.renderOrder = 2
      scene.add(line, glow)
      const lab = new THREE.Mesh(new THREE.PlaneGeometry(3.4, 0.32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ map: branchLabel(half === 0 ? HERO.branch : HERO.peerBranch, T.acct[acct]), transparent: true, depthWrite: false, opacity: 0.8 }))
      const p0 = curve.getPointAt(0.1)
      const tg = curve.getTangentAt(0.1)
      lab.position.set(p0.x, 0.013, p0.z)
      lab.rotation.y = Math.atan2(-tg.x, -tg.z) + Math.PI / 2
      lab.translateX(0.35)
      lab.translateZ(-1.95)
      lab.renderOrder = 4
      scene.add(lab)
      onFloor(line, glow, lab)
      return { curve, line, glow, lab }
    })
    Object.assign(S, { hc, ht, hero, heroLines, heroSig: '' })

    // The gate: two brushed-metal posts on plinths, a lintel carrying a backlit sign, and an arm that
    // lifts for one land at a time. The arm's stripe and the two lamps on the lintel light green while
    // a land passes (green = landed), and are dark otherwise.
    const gate = new THREE.Group()
    const postGeo = new RoundedBoxGeometry(0.26, 4.2, 0.26, 3, 0.05).translate(0, 2.1, 0)
    const plinthGeo = new RoundedBoxGeometry(0.62, 0.14, 0.62, 3, 0.04).translate(0, 0.07, 0)
    const parts = []
    for (const x of [-1.5, 1.5]) {
      const post = new THREE.Mesh(postGeo, metalMat)
      post.position.x = x
      const plinth = new THREE.Mesh(plinthGeo, darkMetal)
      plinth.position.x = x
      parts.push(post, plinth)
    }
    // Tall enough that the lifted arm clears the lintel and its sign (critique round two, finding 6).
    const lintel = new THREE.Mesh(new RoundedBoxGeometry(3.36, 0.26, 0.32, 3, 0.05), metalMat)
    lintel.position.y = 4.2
    const signBody = new THREE.Mesh(new RoundedBoxGeometry(3.14, 1.1, 0.12, 3, 0.04), darkMetal)
    signBody.position.set(0, 4.85, -0.04)
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(3.0, 1.0), new THREE.MeshBasicMaterial({ map: gateSign, transparent: true }))
    sign.position.set(0, 4.85, 0.03)
    const gateLamp = lampMat(T.green, 0.25)
    const lamps = [-1.2, 1.2].map((x) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.075, 20, 12), gateLamp)
      m.position.set(x, 4.2, 0.17)
      return m
    })
    const armPivot = new THREE.Group()
    armPivot.position.set(-1.39, 1.05, 0.2)
    const arm = new THREE.Mesh(new RoundedBoxGeometry(2.9, 0.14, 0.11, 2, 0.035).translate(1.45, 0, 0), new THREE.MeshPhysicalMaterial({ color: T.gateArm, roughness: 0.35, clearcoat: 0.6, envMapIntensity: L.env }))
    arm.castShadow = true
    const stripeMat = lampMat(T.green, 0.25)
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.035, 0.115).translate(1.55, 0, 0), stripeMat)
    armPivot.add(arm, stripe)
    for (const m of [...parts, lintel, signBody]) m.castShadow = true
    gate.add(...parts, lintel, signBody, sign, ...lamps, armPivot)
    gate.position.set(0, 0, gz)
    addStanding(gate)
    const gatePt = L.pillLight ? new THREE.PointLight(T.green, 0, 7, 2) : null
    if (gatePt) {
      gatePt.position.set(0, 1.4, gz + 0.3)
      scene.add(gatePt)
    }
    S.gate = gate
    S.armPivot = armPivot
    S.gateLamp = gateLamp
    S.stripeMat = stripeMat
    S.gatePt = gatePt

    // origin/main and ~/.claude, painted on the floor after the gate.
    const mw = new THREE.Mesh(new THREE.PlaneGeometry(4.4, 0.55).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ map: mainWord, transparent: true, depthWrite: false }))
    mw.rotation.y = Math.PI / 2
    mw.position.set(-0.75, 0.013, gz - 6.5)
    mw.renderOrder = 4
    scene.add(mw)
    onFloor(mw)

    // The racks: ~/.claude, three of them, fed from the trunk by three short links.
    S.racks = RACKS.map((rack, r) => {
      const c = canvas(512 * TEX, 752 * TEX)
      drawRack(c.getContext('2d'), T, 512 * TEX, 752 * TEX, rack, { stale: 0, wave: 1 })
      const t = tex(c)
      // A cabinet: a deep metal body with the rack's face set in it, and a status strip along its top
      // that shows the rack's state (amber while its files are stale, green when live).
      const { g } = panel(RACK_W, RACK_H, t, { depth: 0.7, rim: 0.09, radius: 0.05 })
      const ledMat = lampMat(T.green, dark ? 1.6 : 1)
      const led = new THREE.Mesh(new THREE.BoxGeometry(RACK_W * 0.9, 0.05, 0.02), ledMat)
      led.position.set(0, RACK_H + 0.045, 0.012)
      g.add(led)
      g.position.set(RACK_X[r], LIFT, gz + RACK_Z)
      addStanding(g)
      const sh = floorBlob(RACK_W * 1.2, 1.2, T.shadow, T.shadowA * 0.7)
      sh.position.set(RACK_X[r], 0.003, gz + RACK_Z - 0.1)
      scene.add(sh)
      // A link from the trunk to the rack's foot.
      const lc = new THREE.CubicBezierCurve3(new THREE.Vector3(0, 0, gz + RACK_Z + 4.2), new THREE.Vector3(0, 0, gz + RACK_Z + 2.0), new THREE.Vector3(RACK_X[r], 0, gz + RACK_Z + 2.4), new THREE.Vector3(RACK_X[r], 0, gz + RACK_Z + 0.25))
      const link = new THREE.Mesh(ribbon(lc, 0.08, 40), mkLine(T.green, 1, false, L.lineBoost))
      link.position.y = 0.012
      link.renderOrder = 3
      scene.add(link)
      onFloor(link, sh)
      return { rack, c, t, g, link, ledMat, last: -1 }
    })
    const cw = new THREE.Mesh(new THREE.PlaneGeometry(7.4, 0.93), new THREE.MeshBasicMaterial({ map: claudeWord, transparent: true, depthWrite: false }))
    cw.position.set(0, LIFT + RACK_H + 0.7, gz + RACK_Z)
    scene.add(cw)
    S.claudeWord = cw

    // origin/main's history: a lattice of commits that moves one spacing on per pass (the conveyor),
    // so a land adds a commit at HEAD and nothing is ever undone. HEAD is the ringed point.
    const hist = new THREE.InstancedMesh(dotGeo, new THREE.MeshBasicMaterial({ color: T.dim }), HIST_N)
    hist.frustumCulled = false
    hist.renderOrder = 5
    scene.add(hist)
    onFloor(hist)
    const head = new THREE.Group()
    const hd = new THREE.Mesh(dotGeo, new THREE.MeshBasicMaterial({ color: T.ink, transparent: true }))
    const hr = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: T.green, transparent: true }))
    head.add(hr, hd)
    head.position.set(0, 0.022, gz + HEAD_Z)
    head.renderOrder = 6
    scene.add(head)
    onFloor(head)
    S.hist = hist
    S.head = head
    // The converger's pulse: from HEAD down the trunk to the racks' links.
    const pulse = floorBlob(2.2, 2.2, T.green, dark ? 0.55 : 0.35)
    if (dark) pulse.material.blending = THREE.AdditiveBlending
    pulse.renderOrder = 6
    scene.add(pulse)
    const pulseDot = new THREE.Mesh(dotGeo, lampMat(T.green))
    pulseDot.renderOrder = 7
    scene.add(pulseDot)
    onFloor(pulse, pulseDot)
    S.pulse = pulse
    S.pulseDot = pulseDot

    // Pills: commits in flight. Five fleet pills, the peer's, and the one a force push tries.
    const pillGeo = new THREE.CapsuleGeometry(0.16, 0.5, 6, 16).rotateX(Math.PI / 2).translate(0, 0.17, 0)
    const pillMk = () => {
      const m = new THREE.Mesh(pillGeo, new THREE.MeshBasicMaterial({ color: T.amber, transparent: true }))
      m.renderOrder = 6
      scene.add(m)
      const gl = floorBlob(1.4, 1.4, T.amber, dark ? 0.35 : 0.25)
      if (dark) gl.material.blending = THREE.AdditiveBlending
      scene.add(gl)
      const pt = L.pillLight ? new THREE.PointLight(T.amber, 0, 3.2, 2) : null
      if (pt) scene.add(pt)
      return { m, gl, pt }
    }
    S.pills = [0, 1, 2, 3, 4].map(() => pillMk())
    S.peerPill = pillMk()
    S.ambient = [0, 1, 2].map(() => pillMk())
    S.forcePill = pillMk()

    // The force push's path: a dashed straight cut from a window to origin/main past the gate, and
    // the deny wall that stops it.
    const fo = FLEET[1]
    const fp0 = new THREE.Vector3(fo.x, 0, gz + fo.z - 0.4)
    const fp1 = new THREE.Vector3(0, 0, gz - 4.2)
    S.forcePath = new THREE.LineCurve3(fp0, fp1)
    const dash = new THREE.Mesh(ribbon(S.forcePath, 0.07, 60), mkLine(T.amber, 0.9))
    dash.material.fragmentShader = dash.material.fragmentShader.replace('if (vUv.x > draw', 'if (fract(vUv.x * 26.0) > 0.55) discard;\n        if (vUv.x > draw')
    dash.position.y = 0.014
    dash.renderOrder = 4
    scene.add(dash)
    onFloor(dash)
    S.forceDash = dash
    const wallAt = S.forcePath.getPointAt(0.52)
    const wall = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 1.9).translate(0, 0.95, 0), new THREE.MeshBasicMaterial({ color: T.red, transparent: true, opacity: 0.6, side: THREE.DoubleSide, depthWrite: false }))
    const wallEdge = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 0.14).translate(0, 1.9, 0), new THREE.MeshBasicMaterial({ color: T.red, transparent: true, side: THREE.DoubleSide }))
    const wallBase = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 0.14).translate(0, 0.07, 0), new THREE.MeshBasicMaterial({ color: T.red, transparent: true, side: THREE.DoubleSide }))
    const wg = new THREE.Group()
    wg.add(wall, wallEdge, wallBase)
    wg.position.copy(wallAt)
    const td = S.forcePath.getTangentAt(0.5)
    wg.rotation.y = Math.atan2(td.x, td.z)
    wg.renderOrder = 7
    scene.add(wg)
    S.wall = wg
    S.wallAt = wallAt

    // The card: the one thing that reaches the human.
    const cc = canvas(1024 * TEX, 600 * TEX)
    drawCard(cc.getContext('2d'), T, 1024 * TEX, 600 * TEX)
    const cp = panel(2.1, 1.23, tex(cc), { depth: 0.035, rim: 0.035, radius: 0.045, centre: true, own: true })
    cp.body.material.transparent = true
    cp.screen.renderOrder = 8
    scene.add(cp.g)
    S.card = cp.g
    S.cardParts = cp
    const tether = new THREE.Mesh(new THREE.PlaneGeometry(0.03, 1).translate(0, 0.5, 0), new THREE.MeshBasicMaterial({ color: T.muted, transparent: true, opacity: 0.6, depthWrite: false }))
    scene.add(tether)
    S.tether = tether

    stretches.push(S)
  }

  // The frame: reflection, world, bloom, depth of field, averaged over motion-blur samples (look.js).
  const frame = pipeline(renderer, scene, cam, { width, height, dpr, L, bg: T.bg, floorMat, grain })

  // ------------------------------------------------------------------------------ the camera
  // A pose: position, yaw, pitch, roll, focal length F in px and the principal point (cx, cy). An
  // off-centre principal point is a lens shift: it moves the horizon without tilting the camera, so
  // standing windows stay vertical.
  let cur = { F: 1400, cx: width / 2, cy: height / 2 }
  function pose(p) {
    cur = { F: p.F, cx: p.cx ?? width / 2, cy: p.cy ?? height / 2 }
    // Depth of field focuses where the camera looks (film.js passes the distance).
    cam.userData.focus = p.focus ?? cam.userData.focus ?? 10
    cam.position.set(p.x, p.y, p.z)
    cam.rotation.set(-(p.pitch ?? 0), -(p.yaw ?? 0), p.roll ?? 0)
    const n = cam.near
    const cx = p.cx ?? width / 2
    const cy = p.cy ?? height / 2
    cam.projectionMatrix.makePerspective((-cx / p.F) * n, ((width - cx) / p.F) * n, (cy / p.F) * n, (-(height - cy) / p.F) * n, n, cam.far)
    cam.projectionMatrixInverse.copy(cam.projectionMatrix).invert()
    cam.updateMatrixWorld(true)
  }
  const v3 = new THREE.Vector3()
  /** Screen position of a world point under the current pose, or null behind the camera. */
  function project(x, y, z) {
    v3.set(x, y, z).applyMatrix4(cam.matrixWorldInverse)
    if (v3.z > -0.05) return null
    const d = -v3.z
    v3.applyMatrix4(cam.projectionMatrix)
    return [(v3.x + 1) * 0.5 * width, (1 - v3.y) * 0.5 * height, d]
  }
  /** The world point the pixel (px, py) shows at view depth d, under the current pose (the pacing probe). */
  function unproject(px, py, d) {
    v3.set(((px - cur.cx) * d) / cur.F, (-(py - cur.cy) * d) / cur.F, -d).applyMatrix4(cam.matrixWorld)
    return [v3.x, v3.y, v3.z]
  }

  // ------------------------------------------------------------------------------ the state
  const bgRekey = new THREE.Color(T.bgRekey)
  const m4 = new THREE.Matrix4()
  /**
   * Apply one moment. st(k) returns stretch k's land state (film.js), and drawHero(canvas, state)
   * paints the originator's window for it.
   */
  function update(st, { fog = [40, 150], rekey = false, drawHero } = {}) {
    scene.fog.near = fog[0]
    scene.fog.far = fog[1]
    const b = rekey ? bgRekey : bg
    scene.background = b
    scene.fog.color.copy(b)
    for (const m of lineMats) {
      m.uniforms.fogColor.value.copy(b)
      m.uniforms.fogNear.value = fog[0]
      m.uniforms.fogFar.value = fog[1]
    }
    for (const S of stretches) {
      const s = st(S.k)
      // The originator's window.
      const sig = s.heroSig
      if (sig !== S.heroSig) {
        drawHero(S.hc, s)
        S.ht.needsUpdate = true
        S.heroSig = sig
      }
      S.heroLines[1].line.material.uniforms.draw.value = s.peerLine
      S.heroLines[1].glow.material.uniforms.draw.value = s.peerLine
      S.heroLines[1].line.material.uniforms.opacity.value = s.peerLineA
      S.heroLines[1].glow.material.uniforms.opacity.value = s.peerLineA * T.glowA * 1.3
      S.heroLines[1].line.material.uniforms.color.value.set(s.peerLanded > 0.5 ? T.green : T.acct[HERO.peerAcct])
      S.heroLines[1].lab.material.opacity = s.peerLineA * clamp01(s.peerLine * 3)
      // The arm: 0 down, 1 up.
      S.armPivot.rotation.z = (Math.PI / 2) * 0.92 * s.arm
      // The lamps and the arm's stripe light green while a land passes.
      const glow = 0.25 + (L.lineBoost - 0.25) * s.arm
      S.gateLamp.color.set(T.green).multiplyScalar(glow)
      S.stripeMat.color.set(T.green).multiplyScalar(glow)
      if (S.gatePt) S.gatePt.intensity = 5 * s.arm
      // Pills in flight.
      S.pills.forEach((pl, n) => placePill(S, pl, s.pills[n]))
      placePill(S, S.peerPill, s.peerPill)
      placePill(S, S.forcePill, s.force)
      // The force push's cut and the wall.
      S.forceDash.material.uniforms.draw.value = s.force ? clamp01(s.force.u / 0.52) * 0.52 : 0
      S.forceDash.material.uniforms.color.value.set(s.force?.red > 0.5 ? T.red : T.amber)
      S.forceDash.material.uniforms.opacity.value = s.force ? 0.9 * s.force.a : 0
      S.wall.visible = s.wall > 0.001
      S.wall.scale.set(1, Math.max(0.001, s.wall), 1)
      S.wall.children.forEach((m, i) => { m.material.opacity = (i === 0 ? 0.6 : 1) * s.wallA })
      // The card.
      S.card.visible = s.card != null
      S.tether.visible = s.card != null && s.card.tether > 0.001
      if (s.card) {
        S.card.position.set(s.card.x, s.card.y, s.card.z)
        S.card.rotation.set(0, s.card.yaw, 0)
        S.card.scale.setScalar(s.card.scale)
        const { body, screen, glass } = S.cardParts
        body.material.opacity = s.card.a
        body.material.depthWrite = s.card.a > 0.999
        body.castShadow = s.card.a > 0.5
        screen.material.opacity = s.card.a
        glass.material.opacity = s.card.a
        S.tether.position.set(s.card.x0, 0, s.card.z0)
        S.tether.scale.set(1, Math.max(0.001, s.card.y - s.card.scale), 1)
        S.tether.material.opacity = 0.6 * s.card.tether
      }
      // origin/main's history, moved on by the conveyor; HEAD stays at the trunk's head.
      const frac = s.conveyor - Math.floor(s.conveyor)
      for (let j = 0; j < HIST_N; j += 1) S.hist.setMatrixAt(j, m4.makeTranslation(0, 0.018, S.gz + HEAD_Z - (j + frac) * HIST_DZ))
      S.hist.instanceMatrix.needsUpdate = true
      S.head.visible = true
      S.head.children[1].material.opacity = frac < 0.02 || frac > 0.98 ? 1 : 0.25
      S.pulse.visible = s.pulse != null
      S.pulseDot.visible = s.pulse != null
      if (s.pulse != null) {
        const z = S.gz + HEAD_Z + (RACK_Z + 4.2 - HEAD_Z) * s.pulse
        S.pulse.position.set(0, 0.006, z)
        S.pulseDot.position.set(0, 0.024, z)
      }
      // The racks light up.
      S.racks.forEach((R, r) => {
        const wave = clamp01(s.wave * 1.25 - r * 0.12)
        const q = `${Math.round(s.stale * 30)}:${Math.round(wave * 90)}`
        if (q !== R.last) {
          drawRack(R.c.getContext('2d'), T, 512 * TEX, 752 * TEX, R.rack, { stale: s.stale, wave })
          R.t.needsUpdate = true
          R.last = q
        }
        // The cabinet's status strip: amber while its files are stale, green once the wave has lit it.
        R.ledMat.color.set(s.stale && wave < 0.999 ? T.amber : T.green).multiplyScalar(dark ? 1.6 : 1)
      })
      // Ambient commits on the poster: the system is running while the headline holds.
      S.ambient.forEach((pl, n) => placePill(S, pl, s.ambient?.[n] ?? null))
    }
  }
  // A pill state: null (hidden) or { curve: 'line'|'peer'|'force'|'trunk', n, u, a, green, red }.
  function placePill(S, pl, ps) {
    pl.m.visible = !!ps && ps.a > 0.001
    pl.gl.visible = pl.m.visible
    if (pl.pt) pl.pt.intensity = 0
    if (!pl.m.visible) return
    let curve
    if (ps.on === 'line') curve = S.lines[ps.n].curve
    else if (ps.on === 'peer') curve = S.heroLines[1].curve
    else if (ps.on === 'force') curve = S.forcePath
    else curve = new THREE.LineCurve3(new THREE.Vector3(0, 0, S.gz + 1.2), new THREE.Vector3(0, 0, S.gz + HEAD_Z))
    const u = clamp01(ps.u)
    const pt = curve.getPointAt(u)
    const tg = curve.getTangentAt(u)
    pl.m.position.set(pt.x, 0.02, pt.z)
    pl.m.rotation.y = Math.atan2(tg.x, tg.z)
    const col = ps.red > 0.5 ? T.red : ps.green > 0.5 ? T.green : T.amber
    pl.m.material.color.set(col).multiplyScalar(L.pillGlow)
    pl.m.material.opacity = ps.a
    if (pl.pt) {
      pl.pt.color.set(col)
      pl.pt.intensity = L.pillLight * ps.a
      pl.pt.position.set(pt.x, 0.45, pt.z)
    }
    pl.gl.material.color.set(col)
    pl.gl.material.opacity = (dark ? 0.35 : 0.25) * ps.a
    pl.gl.position.set(pt.x, 0.005, pt.z)
  }
  // The pill's world position (for the type's chips).
  function pillPoint(S, ps) {
    if (!ps) return null
    let curve
    if (ps.on === 'line') curve = S.lines[ps.n].curve
    else if (ps.on === 'peer') curve = S.heroLines[1].curve
    else if (ps.on === 'force') curve = S.forcePath
    else curve = new THREE.LineCurve3(new THREE.Vector3(0, 0, S.gz + 1.2), new THREE.Vector3(0, 0, S.gz + HEAD_Z))
    return curve.getPointAt(clamp01(ps.u))
  }

  /** Render the current state, or the average of several (motion blur). */
  function render(samples, opts) {
    frame.render(samples, opts)
  }

  return { renderer, scene, cam, pose, project, unproject, update, render, stretches, pillPoint }
}

export { rng }
