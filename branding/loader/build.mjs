// Generates the Zemu loading animation from the brand Z path.
// Outputs: zemu-loader.json (Lottie), frames/*.png, zemu-loader.apng, zemu-loader-preview.gif — all transparent.
// Run: npm install && node build.mjs   (needs ffmpeg on PATH for gif/apng)
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { Resvg } from '@resvg/resvg-js';

const FPS = 60, N = 120;           // 2 s loop; frame N == frame 0
const SIZE = 1080, PX = 512;       // canvas units (room for the ring), raster size
const GREEN = '#39FF14';

// Z path from branding/zemu-icon.svg (triangle subpath dropped; it's animated below).
const Z = 'M90 558.87Q53 558.87 26.5 531.87Q0 504.87 0 467.87Q0 449.87 6.5 433.37Q13 416.87 27 403.87L219 231.87H112Q90 231.87 69 227.87Q48 223.87 34 204.87Q20 185.87 20 140.87Q20 95.87 34 77.37Q48 58.87 69 54.87Q90 50.87 112 50.87H415Q452 50.87 478.5 76.87Q505 102.87 505 139.87Q505 158.87 498 176.37Q491 193.87 479 204.87L292 376.87H427Q450 376.87 470.5 380.87Q491 384.87 504 404.37Q517 423.87 517 468.87Q517 513.87 503.5 532.87Q490 551.87 469.5 555.37Q449 558.87 426 558.87Z';

// Triangle placed mid-right like the app icon PNG (same size as the SVG's triangle).
const TW = 98.35, TH = 113.04, TX = 521, TY = 293;
const C = [TX + TW / 3, TY];                     // triangle centroid
const PIVOT = [(0 + TX + TW) / 2, (50.87 + 558.87) / 2]; // centre of whole mark

// --- easing ---
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const seg = (u, a, b) => clamp((u - a) / (b - a));
const inOutCubic = t => t < .5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
const inOutBack = (t, c = 1.70158) => { const k = c * 1.525;
  return t < .5 ? ((2 * t) ** 2 * ((k + 1) * 2 * t - k)) / 2
                : ((2 * t - 2) ** 2 * ((k + 1) * (t * 2 - 2) + k) + 2) / 2; };

// --- timeline (u in [0,1)) ---
// Z: rests, ramps up to a fast spin, arrives at 360 with momentum and springs back (overshoot jiggle).
const T0 = 0.02, T1 = 0.76, A = 0.5;                                   // A = share of the turn spent accelerating
const ramp = t => { const y = t / A; return (t < A ? A * (y ** 3 - y ** 4 / 2) : A / 2 + t - A) / (1 - A / 2); };
const V = 360 / ((1 - A / 2) * (T1 - T0)), W = 59, DAMP = 14;          // arrival speed (deg/loop), spring freq, damping
const spin = u => u < T1 ? 360 * ramp(seg(u, T0, T1))
  : 360 + V * Math.exp(-DAMP * (u - T1)) * Math.sin(W * (u - T1)) / W * (1 - inOutCubic(seg(u, 0.9, 1)));

// Triangle: juts out to the ring, laps the Z once (trail closes into a full ring), trail catches up, snaps home, shakes.
const D = [C[0] - PIVOT[0], C[1] - PIVOT[1]], D0 = Math.hypot(...D), TH0 = Math.atan2(D[1], D[0]);
const ZMAX = Math.max(...parseZ(Z).map(p => Math.hypot(p.v[0] - PIVOT[0], p.v[1] - PIVOT[1])));
const WH = 0.62 * TH, RING = ZMAX + TH / 2 + 16;                      // trail width at the triangle's centroid, ring clear of the Z
const rho = u => D0 + (RING - D0) * (inOutBack(seg(u, 0.04, 0.16), 1.3) - inOutBack(seg(u, 0.68, 0.79), 1.1));
const head = u => 2 * Math.PI * inOutCubic(seg(u, 0.12, 0.46));       // one lap; ring closes at 0.46
const tail = u => 2 * Math.PI * inOutCubic(seg(u, 0.50, 0.71));       // trail shrinks away just before the Z is upright
const turn = u => Math.PI / 2 * (inOutCubic(seg(u, 0.12, 0.22)) - inOutCubic(seg(u, 0.64, 0.71))); // tip faces forward while orbiting
const shake = u => { const t = seg(u, 0.78, 0.95);                     // damped wiggle after it lands
  return 13 * (1 - t) * Math.exp(-3 * t) * Math.sin(2 * Math.PI * 3.5 * t); };
const at = (u, phi = head(u)) => [PIVOT[0] + rho(u) * Math.cos(TH0 + phi), PIVOT[1] + rho(u) * Math.sin(TH0 + phi)];

// 4-point closed path: tip(right), top, back(left), bottom. [x,y,inX,inY,outX,outY] relative handles.
function triPts() {
  const p = [[TX + TW, TY], [TX, TY - TH / 2], [TX, TY], [TX, TY + TH / 2]];
  return p.map((v, i) => { const a = p[(i + 3) % 4], b = p[(i + 1) % 4];
    return [v[0], v[1], (a[0] - v[0]) / 3, (a[1] - v[1]) / 3, (b[0] - v[0]) / 3, (b[1] - v[1]) / 3]; });
}
const TRI = triPts();

function smear(u) {                                    // stretch factor and direction from the triangle's velocity
  const e = 1e-4, q0 = at(u - e), q1 = at(u + e), vx = q1[0] - q0[0], vy = q1[1] - q0[1], v = Math.hypot(vx, vy) / (2 * e);
  return [1 + Math.min(0.7, v * 0.00018), v ? Math.atan2(vy, vx) : 0];
}
function blob(u) {                                     // the triangle, always a triangle, smeared along its velocity
  const p = at(u), [s, va] = smear(u);
  const rot = head(u) + turn(u) + shake(u) * Math.PI / 180;
  const R2 = (x, y, a) => [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)];
  const xf = (x, y) => { [x, y] = R2(x, y, rot - va); return R2(x * s, y / s, va); }; // orient, stretch on velocity axis
  return TRI.map(t => { const [px, py] = xf(t[0] - C[0], t[1] - C[1]);
    return [px + p[0], py + p[1], ...xf(t[2], t[3]), ...xf(t[4], t[5])]; });
}

const K = 24;                                          // vertices per trail edge (Lottie needs a constant count)
function trail(u) {                                    // tapered comet band from tail angle to head angle
  const h = head(u), t = tail(u), grow = clamp((h - t) / 0.4), r = rho(u);
  const edge = side => [...Array(K).keys()].map(j => { const f = j / (K - 1), [x, y] = at(u, t + (h - t) * f);
    const k = (r + side * WH / smear(u)[0] * f ** 0.9 * grow / 2) / r; // head fits inside the smeared triangle
    return [PIVOT[0] + (x - PIVOT[0]) * k, PIVOT[1] + (y - PIVOT[1]) * k]; });
  const cr = pts => pts.map((p, j) => { const a = pts[j - 1], b = pts[j + 1];   // Catmull-Rom handles
    const i = a && b ? [(a[0] - b[0]) / 6, (a[1] - b[1]) / 6] : [0, 0];
    return [p[0], p[1], i[0], i[1], -i[0], -i[1]]; });
  return [...cr(edge(1)), ...cr(edge(-1).reverse())];
}

// --- SVG path -> Lottie vertices (handles M L H V Q Z, absolute) ---
function parseZ(d) {
  const tok = d.match(/[MLHVQZ]|-?[\d.]+/g); let i = 0, cur = [0, 0]; const pts = [];
  const n = () => +tok[i++];
  while (i < tok.length) { const c = tok[i++];
    if (c === 'M' || c === 'L') { cur = [n(), n()]; pts.push({ v: cur, i: [0, 0], o: [0, 0] }); }
    else if (c === 'H') { cur = [n(), cur[1]]; pts.push({ v: cur, i: [0, 0], o: [0, 0] }); }
    else if (c === 'V') { cur = [cur[0], n()]; pts.push({ v: cur, i: [0, 0], o: [0, 0] }); }
    else if (c === 'Q') { const q = [n(), n()], e = [n(), n()], prev = pts[pts.length - 1];
      prev.o = [2 / 3 * (q[0] - cur[0]), 2 / 3 * (q[1] - cur[1])];
      cur = e; pts.push({ v: e, i: [2 / 3 * (q[0] - e[0]), 2 / 3 * (q[1] - e[1])], o: [0, 0] }); }
  }
  const last = pts[pts.length - 1], first = pts[0]; // closing point duplicates the start
  if (Math.hypot(last.v[0] - first.v[0], last.v[1] - first.v[1]) < 0.01) { first.i = last.i; pts.pop(); }
  return pts;
}
const r2 = x => Math.round(x * 100) / 100;
const lottieShape = pts => ({ c: true, v: pts.map(p => p.v.map(r2)), i: pts.map(p => p.i.map(r2)), o: pts.map(p => p.o.map(r2)) });
const shapeOf = b => lottieShape(b.map(p => ({ v: [p[0], p[1]], i: [p[2], p[3]], o: [p[4], p[5]] })));
const svgPath = b => 'M' + b.map((p, i) => { const q = b[(i + 1) % b.length];
  return `${i ? '' : `${r2(p[0])} ${r2(p[1])}`}C${r2(p[0] + p[4])} ${r2(p[1] + p[5])} ${r2(q[0] + q[2])} ${r2(q[1] + q[3])} ${r2(q[0])} ${r2(q[1])}`; }).join('') + 'Z';

// --- self-check: exact loop seam, ring fully closes, everything stays on canvas ---
const check = (ok, msg) => { if (!ok) throw new Error(msg); };
const eq = (a, b) => JSON.stringify(shapeOf(a)) === JSON.stringify(shapeOf(b));
check(eq(blob(0), blob(1)) && eq(blob(0), TRI) && eq(trail(0), trail(1)) && spin(0) === 0 && spin(1) === 360, 'loop seam mismatch');
check(head(0.48) - tail(0.48) === 2 * Math.PI && tail(0.75) === 2 * Math.PI, 'ring never closes / trail outlasts the spin');
let MAXR = 0;
for (let f = 0; f < N; f++) for (const p of [...blob(f / N), ...trail(f / N)])
  MAXR = Math.max(MAXR, Math.hypot(p[0] - PIVOT[0], p[1] - PIVOT[1]));
check(MAXR < SIZE / 2 - 8, `off canvas: needs ${Math.ceil(MAXR * 2 + 16)}`);

// --- Lottie ---
const lin = { i: { x: [1], y: [1] }, o: { x: [0], y: [0] } };
const frames = [...Array(N + 1).keys()];
const keys = fn => ({ a: 1, k: frames.map(f => ({ t: f, s: [fn(f / N)], ...(f < N ? lin : {}) })) });
const tr = { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } };
const rgb = [0x39, 0xff, 0x14].map(c => r2(c / 255)).concat(1);
const fill = { ty: 'fl', c: { a: 0, k: rgb }, o: { a: 0, k: 100 }, r: 1 };
const lottie = {
  v: '5.7.4', fr: FPS, ip: 0, op: N, w: SIZE, h: SIZE, nm: 'Zemu Loader', ddd: 0, assets: [],
  layers: [{
    ddd: 0, ind: 1, ty: 4, nm: 'mark', sr: 1, ip: 0, op: N, st: 0, bm: 0,
    ks: { o: { a: 0, k: 100 }, p: { a: 0, k: [SIZE / 2, SIZE / 2, 0] }, a: { a: 0, k: [...PIVOT.map(r2), 0] },
          s: { a: 0, k: [100, 100, 100] }, r: keys(u => r2(spin(u))) },
    shapes: [
      { ty: 'gr', nm: 'Z', it: [{ ty: 'sh', ks: { a: 0, k: lottieShape(parseZ(Z)) } }, fill, tr] },
      { ty: 'gr', nm: 'trail', it: [{ ty: 'sh', ks: keys(u => shapeOf(trail(u))) }, fill, tr] },
      { ty: 'gr', nm: 'play', it: [{ ty: 'sh', ks: keys(u => shapeOf(blob(u))) }, fill, tr] },
    ],
  }],
};
writeFileSync('zemu-loader.json', JSON.stringify(lottie));

// --- PNG frames (0..N-1; frame N is frame 0) + previews ---
rmSync('frames', { recursive: true, force: true }); mkdirSync('frames');
const svg = u => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${SIZE} ${SIZE}">
<g fill="${GREEN}" transform="translate(${SIZE / 2} ${SIZE / 2}) rotate(${spin(u)}) translate(${-PIVOT[0]} ${-PIVOT[1]})"><path d="${Z}"/><path d="${svgPath(trail(u))}"/><path d="${svgPath(blob(u))}"/></g></svg>`;
for (let f = 0; f < N; f++)
  writeFileSync(`frames/${String(f).padStart(3, '0')}.png`, new Resvg(svg(f / N), { fitTo: { mode: 'width', value: PX } }).render().asPng());
const ff = (...a) => execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-framerate', String(FPS), ...a]);
ff('-i', 'frames/%03d.png', '-plays', '0', '-f', 'apng', 'zemu-loader.apng');
ff('-i', 'frames/%03d.png', '-vf', 'fps=50,scale=320:-1:flags=lanczos,split[a][b];[a]palettegen=reserve_transparent=1[p];[b][p]paletteuse=alpha_threshold=128', '-loop', '0', 'zemu-loader-preview.gif');
// Roku: every other frame (30 fps) at 256 px, played by roku/components/widgets/ZemuLoader.
const ROKU = '../../roku/images/loader';
rmSync(ROKU, { recursive: true, force: true }); mkdirSync(ROKU, { recursive: true });
ff('-i', 'frames/%03d.png', '-vf', "select='not(mod(n\\,2))',scale=256:256:flags=lanczos", '-fps_mode', 'passthrough', '-start_number', '0', `${ROKU}/%02d.png`);
console.log('ok', (JSON.stringify(lottie).length / 1024).toFixed(0) + ' KB lottie');
