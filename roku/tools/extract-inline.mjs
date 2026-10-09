// Moves inline <script><![CDATA[...]]></script> blocks into sibling .brs files so bsc can validate them.
import fs from 'node:fs'
import path from 'node:path'
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)])
for (const f of walk(process.argv[2]).filter(f => f.endsWith('.xml'))) {
  const xml = fs.readFileSync(f, 'utf8')
  const re = /<script type="text\/brightscript"><!\[CDATA\[([\s\S]*?)\]\]><\/script>/
  const m = xml.match(re)
  if (!m) continue
  const name = path.basename(f, '.xml')
  fs.writeFileSync(path.join(path.dirname(f), name + '.brs'), m[1].replace(/^\n/, ''))
  fs.writeFileSync(f, xml.replace(re, `<script type="text/brightscript" uri="${name}.brs" />`))
  console.log('extracted', f)
}
