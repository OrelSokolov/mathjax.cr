// Generate reference MathML for each dataset formula using real MathJax
// (mathjax-full, TeX input + SerializedMmlVisitor) — the "1-to-1" oracle.
// Usage: node tools/make_reference.js < in.jsonl > out.jsonl
const fs = require("fs");
const readline = require("readline");

const { mathjax } = require("../test/js/node_modules/mathjax-full/js/mathjax.js");
const { AbstractMathItem } = require("../test/js/node_modules/mathjax-full/js/core/MathItem.js");
const { TeX } = require("../test/js/node_modules/mathjax-full/js/input/tex.js");
const { AllPackages } = require("../test/js/node_modules/mathjax-full/js/input/tex/AllPackages.js");
const { SerializedMmlVisitor } = require("../test/js/node_modules/mathjax-full/js/core/MmlTree/SerializedMmlVisitor.js");
const { liteAdaptor } = require("../test/js/node_modules/mathjax-full/js/adaptors/liteAdaptor.js");
const { RegisterHTMLHandler } = require("../test/js/node_modules/mathjax-full/js/handlers/html.js");

RegisterHTMLHandler(liteAdaptor());
const tex = new TeX({ packages: AllPackages.filter(p => p !== "bussproofs") });
const html = mathjax.document("", { InputJax: tex });
const visitor = new SerializedMmlVisitor();

async function main() {
  const rl = readline.createInterface({ input: process.stdin });
  for await (const line of rl) {
    if (!line.trim()) continue;
    const item = JSON.parse(line);
    let mml = null;
    let error = null;
    try {
      const math = new AbstractMathItem(item.tex, tex, "tex/inline", null, false);
      math.compile(html);
      mml = visitor.visitTree(math.root, html);
    } catch (e) {
      error = String(e.message || e).split("\n")[0];
    }
    process.stdout.write(JSON.stringify({
      id: item.id, tex: item.tex, mml_ref: mml, ref_error: error,
    }) + "\n");
  }
}

main().catch(e => { console.error(e); process.exit(1); });
