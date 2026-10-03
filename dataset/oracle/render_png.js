// Oracle: typeset every formula from dataset/manifest.json with the
// ORIGINAL MathJax v3 (mathjax-full) and rasterize to LARGE PNG files.
//
//   cd dataset/oracle && node render_png.js [width-px]
//
// MathJax produces the SVG (typesetting is 100% MathJax); the PNG step
// rasterizes that exact SVG with rsvg-convert at a large fixed width
// (default 2000 px, height follows the aspect ratio).
// Writes dataset/png/<id>.png.
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const { mathjax } = require('mathjax-full/js/mathjax.js');
const { TeX } = require('mathjax-full/js/input/tex.js');
const { SVG } = require('mathjax-full/js/output/svg.js');
const { liteAdaptor } = require('mathjax-full/js/adaptors/liteAdaptor.js');
const { RegisterHTMLHandler } = require('mathjax-full/js/handlers/html.js');
const { AllPackages } = require('mathjax-full/js/input/tex/AllPackages.js');

const RSVG = process.env.RSVG_CONVERT ||
  '/home/oleg/librsvg/target/release/rsvg-convert';

const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
const pngDir = path.join(root, 'png');
fs.mkdirSync(pngDir, { recursive: true });
for (const f of fs.readdirSync(pngDir)) fs.unlinkSync(path.join(pngDir, f)); // full regen

const width = parseInt(process.argv[2] || '2000', 10);

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const tex = new TeX({ packages: AllPackages });
const svg = new SVG({ fontCache: 'local' });
const doc = mathjax.document('', { InputJax: tex, OutputJax: svg });

let failed = 0;
for (const c of manifest.cases) {
  try {
    const node = doc.convert(c.tex, {
      display: !!c.display,
      em: 16,
      ex: 8,
      containerWidth: 80 * 16,
    });
    const html = adaptor.outerHTML(node);
    const m = html.match(/<svg[\s\S]*<\/svg>/);
    if (!m) throw new Error('no <svg> element in converter output');
    // currentColor -> black (MathJax default context color)
    const svgStr = m[0].replace(/currentColor/g, '#000000');
    execFileSync(RSVG, ['-w', String(width), '-b', 'transparent',
      '-o', path.join(pngDir, `${c.id}.png`)],
      { input: svgStr, stdio: ['pipe', 'ignore', 'pipe'] });
  } catch (e) {
    failed++;
    console.error(`FAIL ${c.id}: ${e.message}`);
  }
}

console.log(`rendered ${manifest.cases.length - failed}/${manifest.cases.length} cases at width ${width}px -> dataset/png/`);
process.exit(failed ? 1 : 0);
