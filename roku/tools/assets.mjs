// Generates the Roku image assets: tintable 9-patch shapes, gradients, icons, logos and channel art.
// Run: node tools/assets.mjs   (from the roku/ folder)
import { Resvg } from '@resvg/resvg-js'
import { PNG } from 'pngjs'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const out = path.join(root, 'images')
const zemu = path.resolve(root, '..')
fs.mkdirSync(out, { recursive: true })

const render = (svg, width) => new Resvg(svg, width ? { fitTo: { mode: 'width', value: width } } : {}).render().asPng()
const save = (name, buf) => fs.writeFileSync(path.join(out, name), buf)

// ---- 9-patch rounded rectangles (white, tinted at runtime with blendColor) ----
// Roku 9-patch: 1px border, black pixels on the top/left edges mark the stretchable middle.
function ninePatch(name, r, { stroke = 0 } = {}) {
  const s = r * 2 + 2 // inner image size
  const shape = stroke
    ? `<rect x="${stroke / 2}" y="${stroke / 2}" width="${s - stroke}" height="${s - stroke}" rx="${r - stroke / 2}" fill="none" stroke="#fff" stroke-width="${stroke}"/>`
    : `<rect width="${s}" height="${s}" rx="${r}" fill="#fff"/>`
  const inner = PNG.sync.read(render(`<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}">${shape}</svg>`))
  const png = new PNG({ width: s + 2, height: s + 2 })
  png.data.fill(0)
  for (let y = 0; y < s; y++)
    for (let x = 0; x < s; x++) {
      const si = (y * s + x) * 4, di = ((y + 1) * (s + 2) + x + 1) * 4
      inner.data.copy(png.data, di, si, si + 4)
    }
  const mark = (x, y) => { const i = (y * (s + 2) + x) * 4; png.data[i] = 0; png.data[i + 1] = 0; png.data[i + 2] = 0; png.data[i + 3] = 255 }
  // stretch the 2 middle pixels in both directions
  for (const p of [r + 1, r + 2]) { mark(p, 0); mark(0, p) }
  save(name, PNG.sync.write(png))
}
ninePatch('rr4.9.png', 4)
ninePatch('rr8.9.png', 8)
ninePatch('rr12.9.png', 12)
ninePatch('pill.9.png', 20)
ninePatch('ring8.9.png', 8, { stroke: 4 })
ninePatch('ring4.9.png', 4, { stroke: 2 })
ninePatch('ring12.9.png', 12, { stroke: 3 })

// ---- gradients (white with alpha; tinted with the theme background) ----
function grad(name, w, h, horizontal, stops) {
  const st = stops.map(([o, a]) => `<stop offset="${o}" stop-color="#fff" stop-opacity="${a}"/>`).join('')
  const dir = horizontal ? 'x1="0" y1="0" x2="1" y2="0"' : 'x1="0" y1="0" x2="0" y2="1"'
  save(name, render(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><defs><linearGradient id="g" ${dir}>${st}</linearGradient></defs><rect width="${w}" height="${h}" fill="url(#g)"/></svg>`))
}
// Hero: left fade (Background → transparent) and bottom fade, as in Backdrop() in Hero.kt
grad('grad_left.png', 256, 4, true, [[0, 1], [0.3, 0.92], [0.6, 0.35], [1, 0]])
grad('grad_bottom.png', 4, 256, false, [[0, 0], [0.5, 0], [1, 1]])
grad('grad_up.png', 4, 256, false, [[0, 1], [1, 0]])
grad('grad_down.png', 4, 256, false, [[0, 0], [1, 1]])
grad('grad_card.png', 4, 128, false, [[0, 0], [0.45, 0], [1, 0.9]])

// ---- icons (Material Symbols paths, 24×24, rendered white at 64px) ----
const icons = {
  search: 'M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z',
  home: 'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z',
  favorite: 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
  settings: 'M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z',
  puzzle: 'M20.5 11H19V7c0-1.1-.9-2-2-2h-4V3.5C13 2.12 11.88 1 10.5 1S8 2.12 8 3.5V5H4c-1.1 0-1.99.9-1.99 2v3.8H3.5c1.49 0 2.7 1.21 2.7 2.7s-1.21 2.7-2.7 2.7H2V20c0 1.1.9 2 2 2h3.8v-1.5c0-1.49 1.21-2.7 2.7-2.7 1.49 0 2.7 1.21 2.7 2.7V22H17c1.1 0 2-.9 2-2v-4h1.5c1.38 0 2.5-1.12 2.5-2.5S21.88 11 20.5 11z',
  tv: 'M21,3H3C1.9,3 1,3.9 1,5v12c0,1.1 0.9,2 2,2h5v2h8v-2h5c1.1,0 1.99,-0.9 1.99,-2L23,5C23,3.9 22.1,3 21,3zM21,17H3V5h18V17z',
  movie: 'M18,4l2,4h-3l-2,-4h-2l2,4h-3l-2,-4H8l2,4H7L5,4H4C2.9,4 2.01,4.9 2.01,6L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V4H18z',
  anime: 'M12,2l2.4,6.6L21,11l-6.6,2.4L12,20l-2.4,-6.6L3,11l6.6,-2.4L12,2zM19,15l1.1,2.9L23,19l-2.9,1.1L19,23l-1.1,-2.9L15,19l2.9,-1.1L19,15z',
  play: 'M8,5v14l11,-7z',
  pause: 'M6,19h4V5H6v14zM14,5v14h4V5h-4z',
  replay10: 'M12,5V1L7,6l5,5V7c3.31,0 6,2.69 6,6s-2.69,6 -6,6s-6,-2.69 -6,-6H4c0,4.42 3.58,8 8,8s8,-3.58 8,-8S16.42,5 12,5z',
  forward10: 'M12,5V1l5,5l-5,5V7c-3.31,0 -6,2.69 -6,6s2.69,6 6,6s6,-2.69 6,-6h2c0,4.42 -3.58,8 -8,8s-8,-3.58 -8,-8S7.58,5 12,5z',
  add: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  check: 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
  star: 'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z',
  refresh: 'M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z',
  next: 'M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z',
  subtitles: 'M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zM4 12h4v2H4v-2zm10 6H4v-2h10v2zm6 0h-4v-2h4v2zm0-4H10v-2h10v2z',
  audio: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z',
  person: 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
  phone: 'M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z',
  link: 'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z',
  bolt: 'M7 2v11h3v9l7-12h-4l4-8z',
  chat: 'M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z',
  thumbup: 'M1 21h4V9H1v12zm22-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L14.17 1 7.59 7.59C7.22 7.95 7 8.45 7 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z',
  thumbdown: 'M15 3H6c-.83 0-1.54.5-1.84 1.22l-3.02 7.05c-.09.23-.14.47-.14.73v2c0 1.1.9 2 2 2h6.31l-.95 4.57-.03.32c0 .41.17.79.44 1.06L9.83 23l6.59-6.59c.36-.36.58-.86.58-1.41V5c0-1.1-.9-2-2-2zm4 0v12h4V3h-4z',
  info: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z',
  speed: 'M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z',
  aspect: 'M19 12h-2v3h-3v2h5v-5zM7 9h3V7H5v5h2V9zm14-6H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16.01H3V4.99h18v14.02z',
  trash: 'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
  bedtime: 'M12.34 2.02C6.59 1.82 2 6.42 2 12c0 5.52 4.48 10 10 10 3.71 0 6.93-2.02 8.66-5.02-7.51-.25-12.09-8.43-8.32-14.96z',
  heart_outline: 'M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z',
  back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
}
for (const [name, d] of Object.entries(icons)) {
  save(`ic_${name}.png`, render(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64"><path fill="#fff" d="${d}"/></svg>`, 64))
}
// round button background
save('circle.png', render(`<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><circle cx="64" cy="64" r="64" fill="#fff"/></svg>`))
save('circle_ring.png', render(`<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><circle cx="64" cy="64" r="61" fill="none" stroke="#fff" stroke-width="6"/></svg>`))

// ---- logos & channel art from the Zemu branding ----
const embed = (file, w, h) => {
  const b64 = fs.readFileSync(file).toString('base64')
  return render(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}"><image width="${w}" height="${h}" href="data:image/png;base64,${b64}"/></svg>`)
}
save('logo_wordmark.png', embed(path.join(zemu, 'app/src/main/res/drawable-nodpi/logo_wordmark.png'), 348, 83))

// logo_mark(.glow).png and the channel icons come from branding/icons.mjs.
const banner = fs.readFileSync(path.join(zemu, 'branding/zemu-tv-banner.svg'), 'utf8')
save('splash_hd.png', render(banner, 1280))
const crop = (svg, vb, w, h) => svg
  .replace(/viewBox="[^"]*"/, `viewBox="${vb}"`)
  .replace(/width="1280" height="720"/, `width="${w}" height="${h}"`)
  .replace('<rect width="1280" height="720"', '<rect x="-2000" y="-2000" width="6000" height="6000"')

// ---- animated-theme wallpapers (ports of the Android scenes, drawn once) ----
// Each theme gets a still wallpaper (960×540 JPEG, shown at 1280×720) and, for some, a looping
// particle layer: two stacked 640×360 tiles (shown 2×) that the app slides one tile per loop.
let seed = 7
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647)
const W = 1280, H = 720
const svg = (body, w = W, h = H) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`
const lin = (id, stops, x2 = 0, y2 = 1) => `<linearGradient id="${id}" x1="0" y1="0" x2="${x2}" y2="${y2}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join('')}</linearGradient>`
const rad = (id, c, a = 1) => `<radialGradient id="${id}"><stop offset="0" stop-color="${c}" stop-opacity="${a}"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient>`
function wall(name, body) {
  const png = path.join(out, `wall_${name}.png`)
  fs.writeFileSync(png, new Resvg(svg(body), { fitTo: { mode: 'width', value: 960 } }).render().asPng())
  execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '78', png, '--out', path.join(out, `wall_${name}.jpg`)], { stdio: 'ignore' })
  fs.unlinkSync(png)
}
// A particle tile drawn twice (stacked vertically, or side by side when wide) so it loops seamlessly.
function fx(name, draw, wide = false) {
  const tw = 640, th = 360
  const one = draw(tw, th)
  const body = wide ? `${one}<g transform="translate(${tw},0)">${one}</g>` : `${one}<g transform="translate(0,${th})">${one}</g>`
  save(`fx_${name}.png`, render(svg(body, wide ? tw * 2 : tw, wide ? th : th * 2)))
}
const times = (n, f) => Array.from({ length: n }, (_, i) => f(i)).join('')

// Cyberpunk: neon skyline over a magenta horizon and a perspective grid; rain falls.
wall('cyberpunk', `<defs>${lin('s', [[0, '#0B0518'], [0.55, '#2A0B3D'], [0.72, '#FF2A6D', 0.55], [0.73, '#0B0518']])}${rad('g', '#05D9E8', 0.25)}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/><ellipse cx="900" cy="300" rx="420" ry="220" fill="url(#g)"/>
${times(26, i => { const w = 30 + rnd() * 60, h = 90 + rnd() * 300, x = i * 52 - 20; return `<rect x="${x}" y="${520 - h}" width="${w}" height="${h}" fill="#12061F"/>` + times(Math.floor(h / 26), j => rnd() < 0.35 ? `<rect x="${x + 6 + Math.floor(rnd() * (w - 12) / 10) * 10}" y="${520 - h + 10 + j * 26}" width="5" height="8" fill="${rnd() < 0.5 ? '#FF2A6D' : '#05D9E8'}" opacity="0.8"/>` : '') })}
<rect y="520" width="${W}" height="200" fill="#0B0518"/>
${times(14, i => `<line x1="${640 + (i - 7) * 40}" y1="520" x2="${640 + (i - 7) * 260}" y2="720" stroke="#FF2A6D" stroke-opacity="0.35" stroke-width="2"/>`)}
${times(7, i => `<line x1="0" y1="${520 + Math.pow(i / 6, 2) * 200}" x2="${W}" y2="${520 + Math.pow(i / 6, 2) * 200}" stroke="#FF2A6D" stroke-opacity="0.3" stroke-width="2"/>`)}`)
fx('rain', (w, h) => times(70, () => { const x = rnd() * w, y = rnd() * h; return `<line x1="${x}" y1="${y}" x2="${x - 3}" y2="${y + 14}" stroke="#9FE8FF" stroke-opacity="${0.25 + rnd() * 0.35}" stroke-width="1"/>` }))

// Fireflies: a dark forest edge; glowing dots drift up.
wall('fireflies', `<defs>${lin('s', [[0, '#0A1208'], [1, '#050703']])}${rad('m', '#FACC15', 0.18)}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/><circle cx="1050" cy="140" r="260" fill="url(#m)"/>
${times(40, i => { const x = i * 34 - 10, h = 180 + rnd() * 260; return `<path d="M${x} ${H} L${x + 18} ${H - h} L${x + 36} ${H}Z" fill="#0F1A0B" opacity="${0.6 + rnd() * 0.4}"/>` })}
<rect y="660" width="${W}" height="60" fill="#060904"/>`)
fx('fireflies', (w, h) => `<defs>${rad('f', '#FDE68A')}</defs>` + times(26, () => { const r = 3 + rnd() * 5; return `<circle cx="${rnd() * w}" cy="${rnd() * h}" r="${r}" fill="url(#f)"/><circle cx="0" cy="0" r="0"/>` }))

// Matrix: dim columns of glyphs; brighter streaks fall.
const glyphs = 'ｱｲｳｴｵｶｷｸｹｺ01234567890ZEMU'
const col = (x, y0, n, a) => times(n, j => `<text x="${x}" y="${y0 + j * 22}" font-family="monospace" font-size="18" fill="#22C55E" fill-opacity="${(a * (j + 1) / n).toFixed(2)}">${glyphs[Math.floor(rnd() * glyphs.length)]}</text>`)
wall('matrix', `<rect width="${W}" height="${H}" fill="#000500"/>${times(64, i => col(i * 20, rnd() * 300 - 100, 12 + Math.floor(rnd() * 20), 0.22))}`)
fx('matrix', (w, h) => times(14, () => { const x = Math.floor(rnd() * 32) * 20, y = rnd() * h; return times(6, j => `<text x="${x}" y="${y + j * 20}" font-family="monospace" font-size="17" fill="${j === 5 ? '#D9FFE4' : '#4ADE80'}" fill-opacity="${((j + 1) / 6).toFixed(2)}">${glyphs[Math.floor(rnd() * glyphs.length)]}</text>`) }))

// Sakura: a night sky, a moon and a blossoming branch; petals fall.
const petal = (x, y, s, rot, c = '#F9A8D4', a = 0.9) => `<path transform="translate(${x} ${y}) rotate(${rot}) scale(${s})" d="M0 0 C4 -6 10 -4 8 2 C6 7 1 6 0 0Z" fill="${c}" fill-opacity="${a}"/>`
wall('sakura', `<defs>${lin('s', [[0, '#1C0B1A'], [1, '#120810']])}${rad('m', '#FBCFE8', 0.35)}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/><circle cx="1020" cy="180" r="170" fill="url(#m)"/><circle cx="1020" cy="180" r="62" fill="#FCE7F3" opacity="0.85"/>
<path d="M1280 60 C1100 90 980 160 860 260 M1050 120 C1000 60 930 50 880 40 M960 190 C900 220 860 300 840 360" stroke="#2A1420" stroke-width="12" fill="none" stroke-linecap="round"/>
${times(90, () => petal(840 + rnd() * 440, 20 + rnd() * 340, 1.6 + rnd() * 1.6, rnd() * 360, rnd() < 0.5 ? '#F472B6' : '#F9A8D4', 0.55 + rnd() * 0.4))}`)
fx('petals', (w, h) => times(22, () => petal(rnd() * w, rnd() * h, 1 + rnd() * 1.2, rnd() * 360, '#F9A8D4', 0.5 + rnd() * 0.4)))

// Ethereal aurora: soft ribbons of light; sparkles rise.
wall('ethereal', `<defs>${lin('s', [[0, '#0A0918'], [1, '#141030']])}${lin('a', [[0, '#C4B5FD', 0], [0.5, '#A78BFA', 0.5], [1, '#5EEAD4', 0]], 1, 0)}${lin('b', [[0, '#5EEAD4', 0], [0.5, '#67E8F9', 0.35], [1, '#F0ABFC', 0]], 1, 0)}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/>
<path d="M-50 260 C250 120 520 360 800 200 S1200 140 1330 240 L1330 330 C1100 230 900 420 640 320 S200 260 -50 380Z" fill="url(#a)"/>
<path d="M-50 420 C300 300 600 520 900 380 S1200 360 1330 420 L1330 470 C1000 430 800 560 520 470 S100 450 -50 500Z" fill="url(#b)"/>
${times(120, () => `<circle cx="${rnd() * W}" cy="${rnd() * H}" r="${rnd() * 1.6}" fill="#fff" opacity="${0.3 + rnd() * 0.6}"/>`)}`)
fx('sparkles', (w, h) => times(30, () => { const x = rnd() * w, y = rnd() * h, r = 1 + rnd() * 2.5; return `<path d="M${x} ${y - r * 2} L${x + r / 2} ${y} L${x} ${y + r * 2} L${x - r / 2} ${y}Z M${x - r * 2} ${y} L${x} ${y + r / 2} L${x + r * 2} ${y} L${x} ${y - r / 2}Z" fill="#EDE9FE" opacity="${0.4 + rnd() * 0.5}"/>` }))

// PS2 · Y2K: glowing translucent towers on a deep blue-black, with scanlines.
wall('y2k', `<defs>${lin('s', [[0, '#00020A'], [1, '#03123A']])}${lin('t', [[0, '#6FB4FF', 0.05], [1, '#6FB4FF', 0.55]])}${rad('g', '#3B82F6', 0.35)}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/><ellipse cx="640" cy="640" rx="760" ry="200" fill="url(#g)"/>
${times(22, i => { const x = 40 + i * 56 + rnd() * 20, h = 80 + rnd() * 360, w = 18 + rnd() * 16; return `<rect x="${x}" y="${640 - h}" width="${w}" height="${h}" fill="url(#t)"/><rect x="${x}" y="${640 - h}" width="${w}" height="3" fill="#BFE0FF" opacity="0.8"/>` })}
${times(180, i => `<rect y="${i * 4}" width="${W}" height="1" fill="#000" opacity="0.35"/>`)}`)
fx('motes', (w, h) => `<defs>${rad('f', '#9CCBFF')}</defs>` + times(24, () => `<circle cx="${rnd() * w}" cy="${rnd() * h}" r="${2 + rnd() * 3}" fill="url(#f)"/>`))

// Acidwave: technical grid, crosshairs and readouts in acid green.
wall('acidwave', `<rect width="${W}" height="${H}" fill="#0A0A0B"/>
${times(33, i => `<line x1="${i * 40}" y1="0" x2="${i * 40}" y2="${H}" stroke="#C8FF00" stroke-opacity="${i % 4 ? 0.04 : 0.1}"/>`)}${times(19, i => `<line x1="0" y1="${i * 40}" x2="${W}" y2="${i * 40}" stroke="#C8FF00" stroke-opacity="${i % 4 ? 0.04 : 0.1}"/>`)}
<circle cx="1040" cy="200" r="120" fill="none" stroke="#C8FF00" stroke-opacity="0.25" stroke-width="2"/><circle cx="1040" cy="200" r="70" fill="none" stroke="#C8FF00" stroke-opacity="0.15" stroke-dasharray="6 8"/>
<line x1="900" y1="200" x2="1180" y2="200" stroke="#C8FF00" stroke-opacity="0.3"/><line x1="1040" y1="60" x2="1040" y2="340" stroke="#C8FF00" stroke-opacity="0.3"/>
<path d="M0 690 L420 690 L440 670 L1280 670" stroke="#C8FF00" stroke-opacity="0.5" stroke-width="2" fill="none"/>
<text x="1120" y="700" font-family="monospace" font-size="14" fill="#C8FF00" fill-opacity="0.6">ZM-07 // LINK OK</text>
<text x="900" y="360" font-family="monospace" font-size="12" fill="#C8FF00" fill-opacity="0.45">TRK 0.442 · 1.207 · SIG ███▌</text>`)

// Cybercore: the classic teal desktop and a gray taskbar.
wall('retro', `<rect width="${W}" height="${H}" fill="#008080"/>
<rect y="${H - 34}" width="${W}" height="34" fill="#C0C0C0"/><rect y="${H - 34}" width="${W}" height="2" fill="#fff"/>
<rect x="4" y="${H - 30}" width="68" height="26" fill="#C0C0C0" stroke="#000" stroke-width="1"/><rect x="5" y="${H - 29}" width="66" height="1" fill="#fff"/><rect x="5" y="${H - 29}" width="1" height="24" fill="#fff"/>
<text x="26" y="${H - 11}" font-family="sans-serif" font-weight="bold" font-size="14" fill="#000">Start</text>
<rect x="9" y="${H - 25}" width="6" height="6" fill="#F00"/><rect x="16" y="${H - 25}" width="6" height="6" fill="#0A0"/><rect x="9" y="${H - 18}" width="6" height="6" fill="#00F"/><rect x="16" y="${H - 18}" width="6" height="6" fill="#FD0"/>
<rect x="${W - 76}" y="${H - 30}" width="72" height="26" fill="none" stroke="#808080"/><text x="${W - 58}" y="${H - 11}" font-family="sans-serif" font-size="13" fill="#000">12:00</text>`)

// Liquid glass: vivid blurred color fields.
wall('liquid', `<defs>${rad('a', '#0A84FF', 0.9)}${rad('b', '#BF5AF2', 0.75)}${rad('c', '#30D158', 0.55)}${rad('d', '#FF375F', 0.6)}</defs>
<rect width="${W}" height="${H}" fill="#0B1226"/><circle cx="260" cy="180" r="420" fill="url(#a)"/><circle cx="1060" cy="160" r="380" fill="url(#b)"/><circle cx="900" cy="640" r="360" fill="url(#c)"/><circle cx="200" cy="700" r="300" fill="url(#d)"/>
<rect width="${W}" height="${H}" fill="#0B1226" opacity="0.35"/>`)

// 16-Bit: a pixel sky, hills and a brick floor; pixel clouds drift left.
const px = (x, y, w, h, c) => `<rect x="${x * 8}" y="${y * 8}" width="${w * 8}" height="${h * 8}" fill="${c}"/>`
wall('sixteen', `<rect width="${W}" height="${H}" fill="#101848"/>${times(12, i => px(0, i * 5, 160, 5, ['#101848', '#14205A', '#18286C', '#1C3080', '#203894', '#2840A8', '#3048B0', '#3850B8', '#4058C0', '#4860C4', '#5068C8', '#5870CC'][i]))}
${times(9, i => { const cx = i * 20 + 4, w = 14 + Math.floor(rnd() * 10); return times(6, j => px(cx + j, 70 - j * 2, w - j * 2, j * 2 + 2, '#2A7A3A')) })}
${px(0, 70, 160, 10, '#3A9A48')}${px(0, 70, 160, 1, '#5CC46A')}${px(0, 80, 160, 10, '#7A3A1C')}${times(40, i => px((i % 20) * 8 + (Math.floor(i / 20) % 2) * 4, 80 + Math.floor(i / 20) * 5, 7, 4, '#A85A2C'))}
${times(60, () => px(Math.floor(rnd() * 160), Math.floor(rnd() * 40), 1, 1, '#E8E8FF'))}`)
fx('clouds', (w, h) => times(5, i => { const x = Math.floor(rnd() * (w / 8 - 12)), y = 2 + Math.floor(rnd() * 20); return px(x, y, 10, 2, '#F0F0FF') + px(x + 2, y - 1, 6, 1, '#F0F0FF') + px(x + 1, y + 2, 9, 1, '#C8C8F0') }), true)

// Outer space: a nebula and a ringed planet; stars drift.
wall('space', `<defs>${rad('n', '#7C3AED', 0.5)}${rad('m', '#06B6D4', 0.35)}${lin('p', [[0, '#F59E0B'], [1, '#B45309']])}</defs>
<rect width="${W}" height="${H}" fill="#05060F"/><ellipse cx="380" cy="300" rx="520" ry="260" fill="url(#n)"/><ellipse cx="900" cy="520" rx="420" ry="200" fill="url(#m)"/>
${times(260, () => `<circle cx="${rnd() * W}" cy="${rnd() * H}" r="${rnd() * 1.5}" fill="#fff" opacity="${0.3 + rnd() * 0.7}"/>`)}
<circle cx="1080" cy="170" r="80" fill="url(#p)"/><ellipse cx="1080" cy="170" rx="140" ry="26" fill="none" stroke="#FCD34D" stroke-opacity="0.7" stroke-width="5" transform="rotate(-18 1080 170)"/>`)
fx('stars', (w, h) => times(50, () => `<circle cx="${rnd() * w}" cy="${rnd() * h}" r="${0.6 + rnd() * 1.4}" fill="#fff" opacity="${0.4 + rnd() * 0.6}"/>`), true)

// Ocean: deep water with light rays and a seabed; bubbles rise.
wall('ocean', `<defs>${lin('s', [[0, '#0E6A9A'], [0.5, '#06375C'], [1, '#021A2E']])}${lin('r', [[0, '#BAE6FD', 0.22], [1, '#BAE6FD', 0]])}</defs>
<rect width="${W}" height="${H}" fill="url(#s)"/>${times(6, i => `<path d="M${150 + i * 200} 0 L${230 + i * 200} 0 L${360 + i * 220} ${H} L${220 + i * 220} ${H}Z" fill="url(#r)"/>`)}
<path d="M0 640 C200 610 360 660 560 630 S900 600 1280 640 L1280 720 L0 720Z" fill="#0B2A3A"/>
${times(9, i => { const x = 60 + i * 140 + rnd() * 40; return `<path d="M${x} 650 C${x - 20} 590 ${x + 20} 560 ${x} 500" stroke="#14532D" stroke-width="8" fill="none" stroke-linecap="round"/>` })}`)
fx('bubbles', (w, h) => times(26, () => { const r = 2 + rnd() * 6; return `<circle cx="${rnd() * w}" cy="${rnd() * h}" r="${r}" fill="#E0F7FF" fill-opacity="0.12" stroke="#E0F7FF" stroke-opacity="0.6" stroke-width="1.2"/>` }))
console.log('assets written to', out)
