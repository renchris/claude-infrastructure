// tools/hero-film/look.js: the production look (round 3, README § Round 3).
//
// The operator's fourth verdict asked for a scene that "looks like a production environment and not
// just a base virtual environment". Round two drew every surface unlit, on a flat floor, with mirrored
// twins for reflections. This module is what replaces that: physically lit materials under an
// environment map, a real floor with glossy blurred reflections (a mirrored camera, not mirrored
// geometry, so the lighting in a reflection is right), bloom on what emits light, a shallow depth of
// field, and a finishing pass (a highlight roll-off that leaves GitHub's page colour exact, a vignette
// into that colour, dither, and grain in the FILM only).
//
// Every pass is a pure function of the posed scene: nothing here keeps time, so any frame renders the
// same pixels on every run (tools/hero-film/lib.js).

import * as THREE from 'three'
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js'
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js'
import { RectAreaLightUniformsLib } from 'three/addons/lights/RectAreaLightUniformsLib.js'

// Floor-level things (lines, their labels, glows, commit dots) are drawn in the main pass only: they
// lie on the mirror plane, so their reflection would coincide with them.
export const LAYER_FLOOR = 1

// Per grade. Colour still means one thing each (lib.js THEMES); the look only lights it.
export const LOOKS = {
  dark: {
    knee: 0.72, // linear: above this, highlights roll off; the page colour (0.004) is untouched
    bloom: { strength: 0.5, radius: 0.5, threshold: 1.0 },
    lineBoost: 2.4, // emissive lines and pills go above the bloom threshold
    pillGlow: 3.2,
    screen: 1.0, // screens stay under the threshold, so their text never haloes
    reflect: 0.55, reflectBlur: 1.6,
    floor: '#10151d', floorRough: 0.45, floorSpec: 0.25, seam: '#1a212c', seamA: 0.6, floorEnv: 0.04,
    env: 0.55, glass: 1.0,
    hemi: ['#9fb4d6', '#07090d', 0.3], key: ['#dfe7ff', 1.6], rim: ['#6f8cff', 0.7],
    screenLight: 3.2, pillLight: 2.2,
    metal: '#3a414b', metalHi: '#8b949e', body: '#1c2128',
    vignette: 0.34, dof: 2.6, motes: 900,
  },
  light: {
    knee: 0.985,
    bloom: { strength: 0, radius: 0, threshold: 1 }, // on a white page every pixel is at the threshold: bloom would veil the type
    lineBoost: 1.0,
    pillGlow: 1.0,
    screen: 1.0,
    reflect: 0.2, reflectBlur: 2.0,
    floor: '#ffffff', floorRough: 0.6, floorSpec: 0.5, seam: '#e3e8ee', seamA: 0.8, floorEnv: 0.35,
    env: 0.8, glass: 0.1,
    hemi: ['#ffffff', '#d8dee4', 1.25], key: ['#ffffff', 1.0], rim: ['#dfe8ff', 0.3],
    screenLight: 0, pillLight: 0,
    metal: '#6e7781', metalHi: '#afb8c1', body: '#6e7781', // bezels two steps darker than the page, as round one's panes
    vignette: 0.0, dof: 2.2, motes: 0,
  },
}

/** The environment map every metal and glass surface reflects: a lit room, prefiltered. */
export function environment(renderer) {
  const pm = new THREE.PMREMGenerator(renderer)
  const env = pm.fromScene(new RoomEnvironment(), 0.04).texture
  pm.dispose()
  return env
}

export function initAreaLights() {
  RectAreaLightUniformsLib.init()
}

/**
 * The floor: a large plane lit like everything else, with seams every 4 units (the old grid, now
 * inlaid, still reads a flight's speed), a faint variation in roughness, and the blurred reflection
 * of everything standing on it, stronger at grazing angles (Fresnel).
 */
export function floorMaterial(L, fogged = true) {
  // specularIntensity tames the lights' broad glint on a rough floor; the sharp reflection is look.js's own.
  const m = new THREE.MeshPhysicalMaterial({ color: L.floor, roughness: L.floorRough, metalness: 0, specularIntensity: L.floorSpec, envMapIntensity: L.floorEnv, fog: fogged })
  const u = { tRefl: { value: null }, uRes: { value: new THREE.Vector2(1, 1) }, uReflK: { value: L.reflect }, uSeam: { value: new THREE.Color(L.seam) }, uSeamA: { value: L.seamA } }
  m.userData.u = u
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u)
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWP;')
      .replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvWP = (modelMatrix * vec4(transformed, 1.0)).xyz;')
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
varying vec3 vWP; uniform sampler2D tRefl; uniform vec2 uRes; uniform float uReflK; uniform vec3 uSeam; uniform float uSeamA;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y); }`)
      .replace('#include <color_fragment>', `#include <color_fragment>
{ vec2 g = abs(fract(vWP.xz / 4.0 - 0.5) - 0.5) * 4.0; vec2 w = fwidth(vWP.xz) + 0.012;
  float seam = 1.0 - min(smoothstep(0.0, w.x, g.x), smoothstep(0.0, w.y, g.y));
  diffuseColor.rgb = mix(diffuseColor.rgb, uSeam, seam * uSeamA); }`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
roughnessFactor *= 0.82 + 0.36 * vnoise(vWP.xz * 0.45) * vnoise(vWP.xz * 1.7 + 3.1);`)
      .replace('#include <opaque_fragment>', `{ vec2 ruv = gl_FragCoord.xy / uRes; ruv.x = 1.0 - ruv.x;
  vec4 R = texture2D(tRefl, ruv);
  float nv = clamp(dot(normalize(vViewPosition), normalize((viewMatrix * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.0, 1.0);
  float fres = uReflK * mix(0.35, 1.0, pow(1.0 - nv, 3.0));
  outgoingLight = mix(outgoingLight, R.rgb / max(R.a, 1e-3), clamp(R.a, 0.0, 1.0) * fres); }
#include <opaque_fragment>`)
  }
  return m
}

// ------------------------------------------------------------------------------ full-screen passes
const VS = 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }'
function pass(fragmentShader, uniforms, extra = {}) {
  return new THREE.ShaderMaterial({ uniforms, vertexShader: VS, fragmentShader, depthTest: false, depthWrite: false, ...extra })
}
// A 9-tap Gaussian along one direction, on premultiplied colour (the reflection's alpha is coverage).
const BLUR = `uniform sampler2D src; uniform vec2 dir; varying vec2 vUv;
void main() {
  vec4 c = texture2D(src, vUv) * 0.2270270270;
  c += (texture2D(src, vUv + dir * 1.3846153846) + texture2D(src, vUv - dir * 1.3846153846)) * 0.3162162162;
  c += (texture2D(src, vUv + dir * 3.2307692308) + texture2D(src, vUv - dir * 3.2307692308)) * 0.0702702703;
  gl_FragColor = c;
}`
// Depth of field: a golden-angle gather of 32 taps, each weighted by whether ITS circle of confusion
// reaches this pixel, so a sharp foreground edge does not bleed over a soft background.
const DOF = `uniform sampler2D src; uniform sampler2D depth; uniform vec2 px; uniform float focus; uniform float K; uniform float cmax; uniform float near; uniform float far;
varying vec2 vUv;
float lin(float d) { return near * far / (far - d * (far - near)); }
float coc(vec2 uv) { float z = lin(texture2D(depth, uv).x); float r = 1.0 - focus / z; return min(cmax, K * (r > 0.0 ? r : -0.12 * r)); }
void main() {
  float c0 = coc(vUv);
  vec4 base = texture2D(src, vUv);
  if (c0 < 0.35) { gl_FragColor = base; return; }
  vec3 acc = base.rgb; float wsum = 1.0;
  for (int i = 1; i < 32; i++) {
    float r = sqrt(float(i) / 31.0) * c0; float a = float(i) * 2.39996323;
    vec2 uv = vUv + vec2(cos(a), sin(a)) * r * px;
    float cs = coc(uv);
    float w = smoothstep(r - 0.75, r + 0.25, max(cs, c0 * 0.5));
    acc += texture2D(src, uv).rgb * w; wsum += w;
  }
  gl_FragColor = vec4(acc / wsum, 1.0);
}`
// The finish: highlights above the knee roll off (continuous, C1), below it the picture is untouched,
// so the page colour and every surface colour stays exact; a vignette falls toward the page colour, a
// fixed dither breaks banding in the dark floor glow, and grain (FILM only) moves frame to frame.
const FINISH = `uniform sampler2D src; uniform float knee; uniform vec3 bg; uniform float vig; uniform float grain; uniform float seed; uniform vec2 res;
varying vec2 vUv;
float h(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
vec3 roll(vec3 c) { vec3 k = vec3(knee); vec3 s = vec3(1.0 - knee);
  return mix(c, k + s * (1.0 - exp(-(c - k) / s)), step(k, c)); }
void main() {
  vec3 c = roll(max(texture2D(src, vUv).rgb, 0.0));
  vec2 q = (vUv - 0.5) * vec2(1.0, 0.72) * 2.0;
  c = mix(c, bg, vig * smoothstep(0.62, 1.32, length(q)));
  gl_FragColor = vec4(c, 1.0);
  #include <colorspace_fragment>
  vec2 p = vUv * res;
  gl_FragColor.rgb += (h(p) - 0.5) / 255.0;
  if (grain > 0.0) gl_FragColor.rgb += (h(p + seed * 17.13) - 0.5) * grain / 255.0;
}`

/**
 * The frame pipeline. render(samples) renders the posed world once, or the average of several poses
 * (motion blur): per sample a reflection pass, the main pass, bloom and depth of field; the average in
 * linear light; then the finish, once.
 */
export function pipeline(renderer, scene, cam, { width, height, dpr, L, bg, floorMat, grain = 0 }) {
  const W = Math.round(width * dpr)
  const H = Math.round(height * dpr)
  const HF = THREE.HalfFloatType
  const reflRT = new THREE.WebGLRenderTarget(W / 2, H / 2, { type: HF, samples: 2 })
  const blurA = new THREE.WebGLRenderTarget(W / 4, H / 4, { type: HF })
  const blurB = new THREE.WebGLRenderTarget(W / 4, H / 4, { type: HF })
  const one = new THREE.WebGLRenderTarget(W, H, { type: HF, samples: 4, depthTexture: new THREE.DepthTexture(W, H) })
  const dofRT = new THREE.WebGLRenderTarget(W, H, { type: HF })
  const acc = new THREE.WebGLRenderTarget(W, H, { type: HF })
  const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), L.bloom.strength, L.bloom.radius, L.bloom.threshold)

  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2))
  const qs = new THREE.Scene()
  qs.add(quad)
  const qc = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1)
  const blurMat = pass(BLUR, { src: { value: null }, dir: { value: new THREE.Vector2() } })
  const dofMat = pass(DOF, { src: { value: null }, depth: { value: one.depthTexture }, px: { value: new THREE.Vector2(1 / W, 1 / H) }, focus: { value: 10 }, K: { value: L.dof * dpr }, cmax: { value: 5 * dpr }, near: { value: cam.near }, far: { value: cam.far } })
  const addMat = pass('uniform sampler2D src; uniform float w; varying vec2 vUv; void main() { gl_FragColor = vec4(texture2D(src, vUv).rgb * w, 1.0); }', { src: { value: null }, w: { value: 1 } }, { blending: THREE.AdditiveBlending, transparent: true })
  const bgLin = new THREE.Color(bg)
  const finMat = pass(FINISH, { src: { value: acc.texture }, knee: { value: L.knee }, bg: { value: bgLin }, vig: { value: L.vignette }, grain: { value: grain }, seed: { value: 0 }, res: { value: new THREE.Vector2(W, H) } })
  const draw = (mat, target, clear = true) => {
    quad.material = mat
    renderer.setRenderTarget(target)
    if (clear) renderer.clear()
    renderer.render(qs, qc)
  }

  // The mirror: the same camera reflected in the floor (y = 0), its image flipped left to right so the
  // winding comes out the right way round; the floor samples it at (1 - x, y) of its own pixel.
  const vcam = new THREE.PerspectiveCamera()
  vcam.matrixAutoUpdate = false
  vcam.matrixWorldAutoUpdate = false
  const S = new THREE.Matrix4().makeScale(1, -1, 1)
  const FX = new THREE.Matrix4().makeScale(-1, 1, 1)
  const floorU = floorMat.userData.u
  floorU.uRes.value.set(W, H)

  function renderOne(focus) {
    const bgWas = scene.background
    // 1. The reflection: standing things only, on a transparent clear so alpha is coverage.
    vcam.matrixWorld.multiplyMatrices(S, cam.matrixWorld)
    vcam.matrixWorldInverse.copy(vcam.matrixWorld).invert()
    vcam.projectionMatrix.multiplyMatrices(FX, cam.projectionMatrix)
    vcam.projectionMatrixInverse.copy(vcam.projectionMatrix).invert()
    vcam.near = cam.near
    vcam.far = cam.far
    vcam.layers.set(0)
    scene.background = null
    renderer.setClearColor(0x000000, 0)
    renderer.setRenderTarget(reflRT)
    renderer.clear()
    renderer.render(scene, vcam)
    // Blur it: down to a quarter, then separable Gaussian passes.
    let src = reflRT
    for (let i = 0; i < 2; i += 1) {
      blurMat.uniforms.src.value = src.texture
      blurMat.uniforms.dir.value.set((L.reflectBlur * (i + 1)) / (W / 4), 0)
      draw(blurMat, blurA)
      blurMat.uniforms.src.value = blurA.texture
      blurMat.uniforms.dir.value.set(0, (L.reflectBlur * (i + 1)) / (H / 4))
      draw(blurMat, blurB)
      src = blurB
    }
    floorU.tRefl.value = blurB.texture
    scene.background = bgWas
    // 2. The world.
    renderer.setClearColor(bgWas, 1)
    renderer.setRenderTarget(one)
    renderer.clear()
    renderer.render(scene, cam)
    // 3. Bloom, added into the frame in place.
    if (L.bloom.strength > 0) bloom.render(renderer, null, one, 0, false)
    // 4. Depth of field.
    dofMat.uniforms.src.value = one.texture
    dofMat.uniforms.focus.value = focus
    draw(dofMat, dofRT)
  }

  function render(samples, { seed = 0 } = {}) {
    renderer.setRenderTarget(acc)
    renderer.setClearColor(0x000000, 1)
    renderer.clear()
    const list = samples ?? [() => null]
    list.forEach((apply) => {
      apply()
      renderOne(cam.userData.focus ?? 10)
      addMat.uniforms.src.value = dofRT.texture
      addMat.uniforms.w.value = 1 / list.length
      renderer.autoClear = false
      draw(addMat, acc, false)
      renderer.autoClear = true
    })
    finMat.uniforms.seed.value = seed
    draw(finMat, null)
  }
  return { render }
}
