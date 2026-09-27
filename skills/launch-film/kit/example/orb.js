// The voice orb, v3: cobalt ink blooming in a milk-white sphere (approved prototype: ../gltest/orb3.html).
// One WebGL2 canvas the size of the viewport; each frame draws only the orb's bounding box (gl.scissor).
// The voice drives the flow (phase), the bloom (spread) and puffs (spectral flux); the pattern's scale never changes.
// Pure function of its inputs: nothing here keeps state between frames.

const VS = `#version 300 es
in vec2 p; void main(){ gl_Position = vec4(p, 0, 1); }`;
const FS = `#version 300 es
precision highp float;
out vec4 o;
uniform vec2 uRes, uC; uniform float uDpr, uR;
uniform float uT, uPhase, uE, uLow, uMid, uHigh, uFlux, uWash, uShell, uRest, uAlpha, uShadow;
uniform vec3 uPaper, uDeep, uAccent2;

// ---- noise (Ashima-style simplex 3D, public domain)
vec3 m289(vec3 x){return x-floor(x*(1./289.))*289.;} vec4 m289(vec4 x){return x-floor(x*(1./289.))*289.;}
vec4 perm(vec4 x){return m289(((x*34.)+10.)*x);} vec4 tis(vec4 r){return 1.79284291400159-0.85373472095314*r;}
float snoise(vec3 v){
  const vec2 C=vec2(1./6.,1./3.); const vec4 D=vec4(0.,.5,1.,2.);
  vec3 i=floor(v+dot(v,C.yyy)); vec3 x0=v-i+dot(i,C.xxx);
  vec3 g=step(x0.yzx,x0.xyz); vec3 l=1.-g; vec3 i1=min(g.xyz,l.zxy); vec3 i2=max(g.xyz,l.zxy);
  vec3 x1=x0-i1+C.xxx; vec3 x2=x0-i2+C.yyy; vec3 x3=x0-D.yyy; i=m289(i);
  vec4 p=perm(perm(perm(i.z+vec4(0.,i1.z,i2.z,1.))+i.y+vec4(0.,i1.y,i2.y,1.))+i.x+vec4(0.,i1.x,i2.x,1.));
  float n_=.142857142857; vec3 ns=n_*D.wyz-D.xzx; vec4 j=p-49.*floor(p*ns.z*ns.z);
  vec4 x_=floor(j*ns.z); vec4 y_=floor(j-7.*x_); vec4 x=x_*ns.x+ns.yyyy; vec4 y=y_*ns.x+ns.yyyy; vec4 h=1.-abs(x)-abs(y);
  vec4 b0=vec4(x.xy,y.xy); vec4 b1=vec4(x.zw,y.zw); vec4 s0=floor(b0)*2.+1.; vec4 s1=floor(b1)*2.+1.; vec4 sh=-step(h,vec4(0.));
  vec4 a0=b0.xzyw+s0.xzyw*sh.xxyy; vec4 a1=b1.xzyw+s1.xzyw*sh.zzww;
  vec3 p0=vec3(a0.xy,h.x); vec3 p1=vec3(a0.zw,h.y); vec3 p2=vec3(a1.xy,h.z); vec3 p3=vec3(a1.zw,h.w);
  vec4 nr=tis(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3))); p0*=nr.x; p1*=nr.y; p2*=nr.z; p3*=nr.w;
  vec4 m=max(.5-vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)),0.); m=m*m;
  return 105.*dot(m*m,vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}
float fbm(vec3 p){ return 0.60*snoise(p) + 0.28*snoise(p*2.1 + vec3(1.7,9.2,3.1)) + 0.12*snoise(p*4.3 + vec3(-4.1,2.2,7.3)); }
float hash(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main(){
  vec2 css = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uDpr;
  vec2 q = (css - uC) / uR; q.y = -q.y;          // orb radius = 1, y up
  float ph = uPhase, r = length(q);
  float aa = 2.8 / (uR * uDpr);

  // ---- on the surface below: a soft contact shadow and a faint cobalt tint of transmitted light.
  // Premultiplied black and cobalt, so the orb sits on any warm backdrop (page or stage) unchanged.
  vec2 sp = (q - vec2(0.04, -1.0)) * vec2(0.95, 3.6);
  float shadow = (exp(-dot(sp, sp)) * 0.26 + exp(-dot(q*0.62, q*0.62)) * 0.06) * uShadow;
  vec2 tp = (q - vec2(0.10, -1.08)) * vec2(1.5, 5.0);
  float tint = exp(-dot(tp, tp)) * (0.05 + 0.10*uE) * uShadow;
  float bgA = clamp(shadow*2.8 + tint*3., 0., 1.);
  vec4 P = vec4(0., 0., 0., shadow*bgA);
  float ta = tint*bgA; P = vec4((uDeep*0.9 + uPaper*0.1)*ta, ta) + P*(1. - ta);

  if (r < 1. + aa) {
    float rr = min(r, 0.9995);
    float z = sqrt(1. - rr*rr);
    vec3 n = vec3(q, z);
    // milk: a soft, velvety white body lit by one large window from the upper left
    float lam = 0.5 + 0.5*dot(n, normalize(vec3(-0.55, 0.60, 0.58)));
    vec3 milk = mix(vec3(0.86, 0.855, 0.84), vec3(0.995, 0.99, 0.98), smoothstep(0.1, 0.95, lam));
    // ink: three soft slices through the volume, front to back
    vec3 accC = vec3(0.); float T = 1.;
    vec3 core = vec3(0.10*sin(ph*0.23), -0.18 + 0.06*cos(ph*0.19), 0.) * (1. - uWash);
    float spread = 0.26 + 0.30*uE + 0.10*uLow + 0.30*uRest + 2.4*uWash;
    for (int k = 0; k < 3; k++) {
      float d = 0.15 + 0.35*float(k);
      vec2 lq = q * (1.18 - 0.30*z);                        // fisheye: the glass shell magnifies the centre
      vec3 p = vec3(lq, z*(1. - 2.*d));
      vec3 w = vec3(snoise(p*0.7 + vec3(0., ph*0.18, 0.)), snoise(p*0.7 + vec3(3.1, -ph*0.15, 1.4)), snoise(p*0.7 + vec3(-2.6, 1.1, ph*0.13)));
      vec3 pw = p + w*(0.32 + 0.22*uMid);
      float mass = exp(-dot(pw - core, pw - core) / (spread*spread));
      float shape = fbm(pw*1.05 + vec3(0., -ph*0.08, ph*0.05));
      float ridge = 1. - abs(snoise(pw*1.6 + vec3(ph*0.09, 0., ph*0.04)));
      float rim_ = smoothstep(0.04, 0.30, mass) * (1. - smoothstep(0.55, 0.95, mass));   // tendrils live at the cloud's edge
      float wisp = pow(ridge, 10.) * 0.46 * (rim_ + uWash*0.8) * (1. - 0.45*float(k));
      // in the wash the cloud fills the sphere, so contrast carries the structure: milk channels between ink billows
      float ink = clamp(mass * (mix(0.85, 0.42, uWash) + mix(0.9, 1.45, uWash)*shape) + wisp * (0.55 + 0.6*uHigh), 0., 1.);
      ink = smoothstep(0.06, 0.80, ink) * mix(0.6 + 0.4*z, 1., uWash);
      ink *= 1. - 0.30*float(k)/2.;
      vec3 inkC = mix(uAccent2, uDeep, smoothstep(0.15, 0.70, ink));
      float op = ink * (0.78 - 0.16*float(k));
      accC += T * op * inkC; T *= 1. - op;
    }
    vec3 body = accC + T * milk;
    // soft ink puffs on each attack (spectral flux), rising from the core
    vec2 pc = q - vec2(0.05, -0.1 + 0.25*fract(ph*0.2));
    body = mix(body, uDeep, exp(-dot(pc, pc) * 7.) * uFlux * 0.25);
    // glass shell: the studio window reflected as a soft rounded rectangle, a clear rim, the fresnel of the surroundings
    vec3 R = reflect(vec3(0., 0., -1.), n);
    vec2 wq = (R.xy - vec2(-0.56, 0.54)) / vec2(0.20, 0.15);
    float box = length(max(abs(wq) - vec2(0.55, 0.45), 0.)) - 0.35;
    float win = (1. - smoothstep(-0.25, 0.35, box)) * smoothstep(0.05, 0.4, R.z + 0.6);
    float fres = 0.04 + 0.96 * pow(1. - z, 5.);
    float rim = pow(1. - z, 2.5);
    body = body * mix(0.93 + 0.07*z, 1., uWash);
    body = mix(body, vec3(1.), win * 0.32 * uShell);
    body += (vec3(1.) * rim * 0.12 + uPaper * fres * 0.25) * uShell;
    body += (hash(gl_FragCoord.xy + floor(uT*60.)*vec2(17.1, 31.7)) - 0.5) * 0.022;   // grain
    float m = 1. - smoothstep(1. - aa, 1. + aa, r);
    P = vec4(body*m, m) + P*(1. - m);
  }
  P *= uAlpha;
  // dither the 8-bit output by half a level so the shadow's long falloff does not band
  float dz = (hash(gl_FragCoord.xy*1.37 + floor(uT*60.)*vec2(7.3, 3.9)) - 0.5) / 255.;
  P.a = clamp(P.a + dz, 0., 1.);
  P.rgb = clamp(P.rgb, 0., 1.) * step(0.0001, P.a);
  o = P;
}`;

const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);

export function createOrb(canvas) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(1920 * dpr); canvas.height = Math.round(1080 * dpr);
  const gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, premultipliedAlpha: true, antialias: false, alpha: true });
  if (!gl) throw new Error('no WebGL2');
  const sh = (ty, src) => { const s = gl.createShader(ty); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const pr = gl.createProgram(); gl.attachShader(pr, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FS)); gl.linkProgram(pr);
  if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(pr));
  gl.useProgram(pr);
  const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(pr, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const U = {}; const u = (n) => (U[n] ??= gl.getUniformLocation(pr, n));
  gl.uniform3fv(u('uDeep'), hex('#0A3FB0')); gl.uniform3fv(u('uAccent2'), hex('#5E9BE8'));
  gl.uniform2f(u('uRes'), canvas.width, canvas.height); gl.uniform1f(u('uDpr'), dpr);
  gl.disable(gl.BLEND); gl.clearColor(0, 0, 0, 0);
  const W = canvas.width, H = canvas.height;

  // s: { c:{x,y}, r, alpha, t, phase, E, low, mid, high, flux, wash, shell, rest, shadow, paper }
  return function draw(s) {
    gl.disable(gl.SCISSOR_TEST); gl.viewport(0, 0, W, H); gl.clear(gl.COLOR_BUFFER_BIT);
    if (!(s.alpha > 0.002 && s.r > 0.5)) { gl.finish(); return; }
    const ext = 2.2 * s.r;
    const x0 = Math.max(0, Math.floor((s.c.x - ext) * dpr)), x1 = Math.min(W, Math.ceil((s.c.x + ext) * dpr));
    const y0 = Math.max(0, Math.floor((s.c.y - ext) * dpr)), y1 = Math.min(H, Math.ceil((s.c.y + ext) * dpr));
    if (x1 <= x0 || y1 <= y0) { gl.finish(); return; }
    gl.enable(gl.SCISSOR_TEST); gl.scissor(x0, H - y1, x1 - x0, y1 - y0);
    gl.uniform2f(u('uC'), s.c.x, s.c.y); gl.uniform1f(u('uR'), s.r);
    for (const [k, v] of [['uT', s.t], ['uPhase', s.phase], ['uE', s.E], ['uLow', s.low], ['uMid', s.mid], ['uHigh', s.high], ['uFlux', s.flux],
      ['uWash', s.wash], ['uShell', s.shell], ['uRest', s.rest], ['uAlpha', s.alpha], ['uShadow', s.shadow]]) gl.uniform1f(u(k), v);
    gl.uniform3fv(u('uPaper'), hex(s.paper));
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.finish();
  };
}
