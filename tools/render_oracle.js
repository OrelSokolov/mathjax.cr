// Render SVG via mathjax-full (oracle) for calibration formulas.
// Usage: node tools/render_oracle.js 'tex' [display]
const path = require("path");
const { mathjax } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/mathjax.js"));
const { TeX } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/input/tex.js"));
const { SVG } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/output/svg.js"));
const { AllPackages } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/input/tex/AllPackages.js"));
const { liteAdaptor } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/adaptors/liteAdaptor.js"));
const { RegisterHTMLHandler } = require(path.join(__dirname, "../test/js/node_modules/mathjax-full/js/handlers/html.js"));

const adaptor = liteAdaptor();
RegisterHTMLHandler(adaptor);
const tex = new TeX({ packages: AllPackages.filter(p => p !== "bussproofs") });
const svg = new SVG({ fontCache: "local" });
const html = mathjax.document("", { InputJax: tex, OutputJax: svg });

const src = process.argv[2];
const display = (process.argv[3] || "block") === "block";
const node = html.convert(src, { display });
const out = adaptor.outerHTML(node);
// strip the font-cache defs wrapper for readability
console.log(out.replace(/\n/g, ""));
