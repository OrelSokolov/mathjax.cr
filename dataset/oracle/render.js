// Oracle: render every formula from dataset/manifest.json with the
// ORIGINAL MathJax v3 (mathjax-full) into reference SVG files.
//
//   cd dataset/oracle && npm install && node render.js
//
// Writes dataset/inputs/<id>.tex and dataset/expected/<id>.svg.
'use strict';

const fs = require('fs');
const path = require('path');

const { mathjax } = require('mathjax-full/js/mathjax.js');
const { TeX } = require('mathjax-full/js/input/tex.js');
const { SVG } = require('mathjax-full/js/output/svg.js');
const { liteAdaptor } = require('mathjax-full/js/adaptors/liteAdaptor.js');
const { RegisterHTMLHandler } = require('mathjax-full/js/handlers/html.js');
const { AllPackages } = require('mathjax-full/js/input/tex/AllPackages.js');

const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
const inputsDir = path.join(root, 'inputs');
const expectedDir = path.join(root, 'expected');
for (const dir of [inputsDir, expectedDir]) {
  fs.mkdirSync(dir, { recursive: true });
  for (const f of fs.readdirSync(dir)) fs.unlinkSync(path.join(dir, f)); // full regen
}

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const tex = new TeX({ packages: AllPackages });
const svg = new SVG({ fontCache: 'local' }); // embed glyph paths -> self-contained SVGs
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
    fs.writeFileSync(path.join(inputsDir, `${c.id}.tex`), c.tex + '\n');
    fs.writeFileSync(path.join(expectedDir, `${c.id}.svg`), adaptor.outerHTML(node) + '\n');
  } catch (e) {
    failed++;
    console.error(`FAIL ${c.id}: ${e.message}`);
  }
}

console.log(`rendered ${manifest.cases.length - failed}/${manifest.cases.length} cases`);
process.exit(failed ? 1 : 0);
