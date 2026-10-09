// Generates the Roku image assets: tintable 9-patch shapes, gradients, icons, logos and channel art.
// Run: node tools/assets.mjs   (from the roku/ folder)
import { Resvg } from '@resvg/resvg-js'
import { PNG } from 'pngjs'
import fs from 'node:fs'
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
save('logo_mark.png', embed(path.join(zemu, 'app/src/main/res/drawable-nodpi/logo_mark.png'), 92, 82))
save('logo_wordmark.png', embed(path.join(zemu, 'app/src/main/res/drawable-nodpi/logo_wordmark.png'), 348, 83))

const banner = fs.readFileSync(path.join(zemu, 'branding/zemu-tv-banner.svg'), 'utf8')
save('splash_hd.png', render(banner, 1280))
const crop = (svg, vb, w, h) => svg
  .replace(/viewBox="[^"]*"/, `viewBox="${vb}"`)
  .replace(/width="1280" height="720"/, `width="${w}" height="${h}"`)
  .replace('<rect width="1280" height="720"', '<rect x="-2000" y="-2000" width="6000" height="6000"')
save('icon_hd.png', render(crop(banner, '96 -48 1088 816', 290, 218), 290))
save('icon_fhd.png', render(crop(banner, '96 -48 1088 816', 540, 405), 540))
console.log('assets written to', out)
