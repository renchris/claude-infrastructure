// Renders composition/index.html (or --page <path>) frame by frame with chrome-headless-shell over CDP.
//   node render.mjs stills [--dpr 1] t1 t2 ...        -> stills/t-<t>.png (1920x1080)
//   node render.mjs video  [--dpr 2] [--from s] [--to s] -> out/frames.mkv (1920x1080 FFV1, lossless RGB; YUV happens once, at the final encode)
//   node render.mjs geom   [--geom-dir d] [--shots 6]    -> d/geom.jsonl + glyph-less screenshots: picture_gate.py's evidence
//   node render.mjs cues                                 -> the page's window.__cues() (the score's clock)
// The server's root is the repository, so the composition loads the real article, popup and icon from it.
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const CHROME = process.env.CHROME || `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const args = process.argv.slice(2);
const mode = args.shift();
const opt = (k, d) => { const i = args.indexOf(`--${k}`); if (i < 0) return d; const v = args[i + 1]; args.splice(i, 2); return v; };
const DPR = Number(opt('dpr', mode === 'video' ? '2' : '1'));
const FROM = Number(opt('from', '0'));
const TO = opt('to', null);
const OUT = opt('out', join(HERE, 'out', 'frames.mkv'));
const SUB = Number(opt('sub', '1'));   // subframes per frame: motion blur over a 180-degree shutter
const SIZE = opt('size', '1920:1080');   // output size; 3840:2160 keeps every captured pixel at --dpr 2
const PAGE = opt('page', 'composition/index.html');   // a prototype page (the signature object alone) renders through the same contract
const STILLS = opt('stills-dir', 'stills');

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.ttf': 'font/ttf', '.woff2': 'font/woff2', '.webp': 'image/webp', '.jpg': 'image/jpeg', '.wav': 'audio/wav' };
const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = resolve(REPO, `.${path}`);
  if (!file.startsWith(REPO) || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  try { const body = await readFile(file); res.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' }); res.end(body); }
  catch { res.writeHead(500); res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const HTTP = `http://127.0.0.1:${server.address().port}`;

const profile = await mkdtemp(join(tmpdir(), 'brag-chrome-'));
const chrome = spawn(CHROME, [
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', '--hide-scrollbars',
  '--force-color-profile=srgb', '--run-all-compositor-stages-before-draw', '--disable-background-timer-throttling',
  '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--font-render-hinting=none', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
const wsBrowser = await new Promise((res, rej) => {
  let buf = '';
  const to = setTimeout(() => rej(new Error('chrome did not start')), 20000);
  chrome.stderr.on('data', (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\S+)/); if (m) { clearTimeout(to); res(m[1]); } });
});
const port = new URL(wsBrowser).port;
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page = targets.find((t) => t.type === 'page');
const sock = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => { sock.onopen = r; });
let seq = 0; const pending = new Map();
sock.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.rej(new Error(JSON.stringify(m.error))) : p.res(m.result); } else if (m.method === 'Runtime.consoleAPICalled') { console.error('[page]', m.params.type, m.params.args.map((a) => a.value ?? a.description).join(' ')); } else if (m.method === 'Runtime.exceptionThrown') { console.error('[page exception]', m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text); } };
// a renderer that dies mid-call never answers: fail loudly after 90 s instead of waiting forever (seen at frame ~499)
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = ++seq, to = setTimeout(() => { pending.delete(id); rej(new Error(`CDP ${method} timed out (renderer gone?)`)); }, 90000);
  pending.set(id, { res: (v) => { clearTimeout(to); res(v); }, rej: (e) => { clearTimeout(to); rej(e); } }); sock.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) => { const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text); return r.result.value; };

await send('Runtime.enable'); await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: DPR, mobile: false });
await send('Page.navigate', { url: `${HTTP}/${relative(REPO, HERE)}/${PAGE}` });
for (let i = 0; ; i++) { if (await evaluate('window.__ready === true').catch(() => false)) break; if (i > 300) throw new Error('composition never became ready'); await new Promise((r) => setTimeout(r, 100)); }
const info = await evaluate('window.__info()');
console.error('ready', JSON.stringify(info));
const shot = async (t) => { await evaluate(`window.__render(${t})`); const { data } = await send('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true, captureBeyondViewport: false }); return Buffer.from(data, 'base64'); };
const ff = (a, input) => new Promise((res, rej) => { const p = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...a], { stdio: ['pipe', 'inherit', 'inherit'] }); p.on('exit', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg ${c}`)))); if (input) { p.stdin.end(input); } return p; });

try {
  if (mode === 'geom') {
    // The design gate's evidence: what the page itself says is on screen, every frame. For each visible text run: its
    // boxes, its on-screen glyph size (font-size × the element's own scale), its effective opacity, and whether any
    // ancestor puts it on a skewed, rotated or 3D plane. Every SHOTS-th frame also gets a screenshot with all glyphs made
    // transparent, so the gate can see exactly which strokes and shapes sit inside a text box. Generic: it needs nothing
    // from the page but the render contract, so it runs on the rejected v2 page as well.
    const GDIR = resolve(HERE, opt('geom-dir', 'out/geom')), SHOTS = Number(opt('shots', '6'))
    await mkdir(GDIR, { recursive: true })
    await evaluate(`window.__geomWalk = () => {
      const W = innerWidth, H = innerHeight, out = []
      window.__gid = window.__gid || new WeakMap(); window.__gseq = window.__gseq || 0
      const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
      for (let n; (n = tw.nextNode());) {
        if (!n.nodeValue.trim()) continue
        const el = n.parentElement; if (!el) continue
        let op = 1, texture = false, role = null, skew = false
        for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
          const c = getComputedStyle(e)
          if (c.display === 'none' || c.visibility === 'hidden') { op = 0; break }
          op *= +c.opacity
          if (e.hasAttribute('data-texture')) texture = true
          if (!role && e.dataset && e.dataset.role) role = e.dataset.role
          if (c.transform && c.transform !== 'none') { const m = new DOMMatrix(c.transform); if (!m.is2D || Math.abs(m.b) > 0.005 || Math.abs(m.c) > 0.005) skew = true }
        }
        const cs = getComputedStyle(el), col = cs.color.match(/[\\d.]+/g) || [], ca = col.length > 3 ? +col[3] : 1
        op *= ca
        if (op < 0.05) continue
        const rg = document.createRange(); rg.selectNodeContents(n)
        const rects = [...rg.getClientRects()].filter((q) => q.width > 0.5 && q.height > 0.5 && q.right > 0 && q.bottom > 0 && q.left < W && q.top < H)
          .map((q) => [+q.left.toFixed(1), +q.top.toFixed(1), +q.width.toFixed(1), +q.height.toFixed(1)])
        if (!rects.length) continue
        const br = el.getBoundingClientRect(), sc = el.offsetWidth > 0 ? br.width / el.offsetWidth : 1
        if (!window.__gid.has(el)) window.__gid.set(el, ++window.__gseq)
        out.push({ id: window.__gid.get(el), s: n.nodeValue.trim().slice(0, 48), px: +(parseFloat(cs.fontSize) * sc).toFixed(1), op: +op.toFixed(3), role, texture, skew, rects })
      }
      return out
    }`)
    const NOTEXT = `*, *::before, *::after { color: transparent !important; -webkit-text-fill-color: transparent !important; text-shadow: none !important; } [data-glyph] { visibility: hidden !important; }`  // colour emoji ignore color: pages mark them data-glyph
    const fps = info.fps, n0 = Math.round(FROM * fps), n1 = Math.round((TO == null ? info.duration : Number(TO)) * fps)
    const lines = []
    for (let n = n0; n < n1; n++) {
      await evaluate(`window.__render(${n / fps})`)
      const texts = await evaluate('window.__geomWalk()')
      let shotFile = null
      if (n % SHOTS === 0) {
        await evaluate(`(() => { const s = document.createElement('style'); s.id = '__notext'; s.textContent = ${JSON.stringify(NOTEXT)}; document.head.appendChild(s) })()`)
        await evaluate('new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))')
        const { data } = await send('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true })
        shotFile = `notext-${String(n).padStart(5, '0')}.png`
        await (await import('node:fs/promises')).writeFile(join(GDIR, shotFile), Buffer.from(data, 'base64'))
        await evaluate(`document.getElementById('__notext').remove()`)
      }
      lines.push(JSON.stringify({ n, t: +(n / fps).toFixed(4), texts, shot: shotFile }))
      if (n % 120 === 0) console.error(`geom ${n}/${n1}`)
    }
    await (await import('node:fs/promises')).writeFile(join(GDIR, 'geom.jsonl'), lines.join('\n') + '\n')
    await (await import('node:fs/promises')).writeFile(join(GDIR, 'info.json'), JSON.stringify({ ...info, page: PAGE, n0, n1, shots: SHOTS }))
    console.log(GDIR, n1 - n0, 'frames')
  } else if (mode === 'cues') {
    console.log(JSON.stringify(await evaluate('window.__cues()')))
  } else if (mode === 'eval') {
    console.log(JSON.stringify(await evaluate(args.join(' '))))
  } else if (mode === 'stills') {
    await mkdir(join(HERE, STILLS), { recursive: true });
    for (const t of args.map(Number)) {
      const png = await shot(t);
      const out = join(HERE, STILLS, `t-${t.toFixed(2)}.png`);
      if (DPR === 1) await (await import('node:fs/promises')).writeFile(out, png);
      else await ff(['-f', 'png_pipe', '-i', '-', '-vf', 'scale=1920:1080:flags=lanczos', out], png);
      console.log(out);
    }
  } else if (mode === 'video') {
    await mkdir(dirname(OUT), { recursive: true });
    const fps = info.fps, n0 = Math.round(FROM * fps), n1 = Math.round((TO == null ? info.duration : Number(TO)) * fps);
    // SUB subframes per output frame at t = (n + ((k + 0.5) / SUB - 0.5) * 0.5) / fps, averaged by tmix: a 180-degree shutter
    const blur = SUB > 1 ? `tmix=frames=${SUB},select='eq(mod(n\\,${SUB})\\,${SUB - 1})',setpts=N/(${fps}*TB),` : '';
    const enc = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(fps * SUB), '-c:v', 'png', '-i', '-',
      '-vf', `${blur}scale=${SIZE}:flags=lanczos+accurate_rnd+full_chroma_int,format=gbrp`, '-r', String(fps), '-c:v', 'ffv1', '-level', '3', '-g', '1', OUT], { stdio: ['pipe', 'inherit', 'inherit'] });
    const done = new Promise((res, rej) => enc.on('exit', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg ${c}`)))));
    const t0 = Date.now();
    for (let n = n0; n < n1; n++) for (let k = 0; k < SUB; k++) {
      const png = await shot(SUB > 1 ? (n + ((k + 0.5) / SUB - 0.5) * 0.5) / fps : n / fps);
      if (!enc.stdin.write(png)) await new Promise((r) => enc.stdin.once('drain', r));
      if (n % 30 === 0 && k === 0) console.error(`frame ${n}/${n1} ${((Date.now() - t0) / 1000).toFixed(1)}s`);
    }
    enc.stdin.end();
    await done;
    console.log(OUT, n1 - n0, 'frames', ((Date.now() - t0) / 1000).toFixed(1), 's');
  } else throw new Error(`unknown mode ${mode}`);
} finally {
  sock.close(); chrome.kill('SIGTERM'); server.close();
  await rm(profile, { recursive: true, force: true }).catch(() => {});
}
