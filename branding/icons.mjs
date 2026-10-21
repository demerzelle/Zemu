// Generates every app's icon and side-menu mark from one Zemu mark (Z + triangle, mid-right).
// Run from branding/: npm install && node icons.mjs   (needs cwebp for the Android launcher icons)
// Side-menu marks are white so each app can tint them with the theme's accent color;
// the *_glow.png files are a blurred copy for the pulsing glow behind them.
import { writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { Resvg } from '@resvg/resvg-js';

const GREEN = '#39FF14', PURPLE = '#3B0A72';
const Z = 'M90 558.87Q53 558.87 26.5 531.87Q0 504.87 0 467.87Q0 449.87 6.5 433.37Q13 416.87 27 403.87L219 231.87H112Q90 231.87 69 227.87Q48 223.87 34 204.87Q20 185.87 20 140.87Q20 95.87 34 77.37Q48 58.87 69 54.87Q90 50.87 112 50.87H415Q452 50.87 478.5 76.87Q505 102.87 505 139.87Q505 158.87 498 176.37Q491 193.87 479 204.87L292 376.87H427Q450 376.87 470.5 380.87Q491 384.87 504 404.37Q517 423.87 517 468.87Q517 513.87 503.5 532.87Q490 551.87 469.5 555.37Q449 558.87 426 558.87Z';
// Same triangle as the loader (branding/loader/build.mjs): left edge x=521, centred on y=293.
const TRI = 'M521 236.48L521 349.52L619.35 293Z';
const MARK = Z + TRI;
const BOX = { x: 0, y: 50.87, w: 619.35, h: 508 }; // the mark's bounds

const out = (p) => new URL(`../${p}`, import.meta.url).pathname;
const png = (svg, w) => new Resvg(svg, { fitTo: { mode: 'width', value: w } }).render().asPng();
const write = (p, data) => { mkdirSync(out(p).replace(/\/[^/]+$/, ''), { recursive: true }); writeFileSync(out(p), data); };

/** The mark scaled so its width is [frac] of a [size]² canvas, centred. */
function placed(size, frac, fill, extra = '') {
  const s = (size * frac) / BOX.w;
  const tx = (size - BOX.w * s) / 2 - BOX.x * s, ty = (size - BOX.h * s) / 2 - BOX.y * s;
  return `<g transform="translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${s.toFixed(5)})" ${extra}><path fill="${fill}" d="${MARK}"/></g>`;
}
const svg = (w, h, body, defs = '') => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">${defs}${body}</svg>`;

// App icon: purple background (rounded square, circle or full bleed) with the green mark.
const appIcon = (size, shape) => svg(size, size,
  (shape === 'circle' ? `<circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="${PURPLE}"/>`
    : shape === 'bleed' ? `<rect width="${size}" height="${size}" fill="${PURPLE}"/>`
    : `<rect width="${size}" height="${size}" rx="${size * 0.22}" fill="${PURPLE}"/>`) + placed(size, 0.62, GREEN));

// Side-menu mark: tight crop, white (tinted at runtime); glow: blurred, with room to spread.
const markW = 460, markH = Math.round(markW * BOX.h / BOX.w);
const markSvg = (fill) => svg(BOX.w, BOX.h, `<g transform="translate(${-BOX.x} ${-BOX.y})"><path fill="${fill}" d="${MARK}"/></g>`);
const pad = 0.35; // glow canvas is 1 + 2*pad times the mark on each side
const glowSvg = () => {
  const W = BOX.w * (1 + 2 * pad), H = BOX.h + BOX.w * 2 * pad;
  return svg(W.toFixed(1), H.toFixed(1),
    `<g filter="url(#b)" transform="translate(${BOX.w * pad - BOX.x} ${BOX.w * pad - BOX.y})"><path fill="#fff" d="${MARK}"/></g>`,
    `<defs><filter id="b" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${BOX.w * 0.1}"/></filter></defs>`);
};

// ---- branding sources ----
write('branding/zemu-icon.svg', svg(704, 704, placed(704, 0.88, GREEN)) + '\n');
write('branding/zemu-app-icon.svg', appIcon(1024, 'rounded') + '\n');
write('branding/zemu-icon.png', png(svg(704, 704, placed(704, 0.88, GREEN)), 512));

// ---- side-menu marks (every app) ----
const mark = png(markSvg('#fff'), markW), glow = png(glowSvg(), Math.round(markW * (1 + 2 * pad)));
for (const dir of ['app/src/main/res/drawable-nodpi', 'macos/Resources', 'ios/Resources']) write(`${dir}/logo_mark.png`, mark);
// Mac and iPhone draw their glow with a SwiftUI shadow; Android and Roku use this blurred copy.
write('app/src/main/res/drawable-nodpi/logo_mark_glow.png', glow);
write('roku/images/logo_mark.png', png(markSvg('#fff'), 96));
write('roku/images/logo_mark_glow.png', png(glowSvg(), Math.round(96 * (1 + 2 * pad))));

// ---- Android launcher ----
const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
const tmp = out('branding/.tmp'); mkdirSync(tmp, { recursive: true });
for (const [d, k] of Object.entries(dens)) {
  const res = `app/src/main/res/mipmap-${d}`;
  for (const [name, shape] of [['ic_launcher', 'rounded'], ['ic_launcher_round', 'circle']]) {
    writeFileSync(`${tmp}/${name}.png`, png(appIcon(48 * k, shape), 48 * k));
    execFileSync('cwebp', ['-quiet', '-lossless', `${tmp}/${name}.png`, '-o', out(`${res}/${name}.webp`)]);
  }
  // Adaptive-icon foreground (108dp canvas, mark inside the 66dp safe zone).
  write(`${res}/ic_launcher_foreground.png`, png(svg(108 * k, 108 * k, placed(108 * k, 0.6, GREEN)), 108 * k));
}
rmSync(tmp, { recursive: true });
{ // Vector foreground used by the adaptive icon (and the themed monochrome icon).
  const s = (108 * 0.6) / BOX.w, tx = (108 - BOX.w * s) / 2 - BOX.x * s, ty = (108 - BOX.h * s) / 2 - BOX.y * s;
  const d = MARK.replace(/([A-Z])/g, ' $1').trim();
  write('app/src/main/res/drawable/ic_launcher_foreground.xml', `<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
  <!-- Generated by branding/icons.mjs -->
  <group android:translateX="${tx.toFixed(3)}" android:translateY="${ty.toFixed(3)}" android:scaleX="${s.toFixed(5)}" android:scaleY="${s.toFixed(5)}">
    <path android:pathData="${d}" android:fillColor="${GREEN}"/>
  </group>
</vector>
`);
}

// ---- Mac (build-app.sh pads it into the macOS icon grid), iPhone/iPad (opaque, iOS rounds it) ----
write('macos/Resources/AppIcon-1024.png', png(appIcon(1024, 'rounded'), 1024));
write('ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', png(appIcon(1024, 'bleed'), 1024));

// ---- Roku channel icons (purple tile, mark centred) ----
for (const [name, w, h] of [['icon_hd', 290, 218], ['icon_fhd', 540, 405]]) {
  const s = (h * 0.62) / BOX.h;
  const tx = (w - BOX.w * s) / 2 - BOX.x * s, ty = (h - BOX.h * s) / 2 - BOX.y * s;
  write(`roku/images/${name}.png`, png(svg(w, h, `<rect width="${w}" height="${h}" fill="${PURPLE}"/><g transform="translate(${tx} ${ty}) scale(${s})"><path fill="${GREEN}" d="${MARK}"/></g>`), w));
}
if (!existsSync(out('roku/images/icon_hd.png'))) throw new Error('Roku icons missing');
console.log('icons ok');
