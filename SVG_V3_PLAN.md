# SVG output v3 plan: path-based SVG identical to MathJax v3

STATUS (2026-10-03): **complete** — the layout engine is a port of the
v3 common wrappers, not an approximation.

- `tools/gen_svg_fonts.py` → `src/mathjax/fonts/tex_paths.cr`:
  glyph paths (self-check 7920/7920 d-strings byte-equal to
  dataset/expected, including empty-path glyphs such as U+2061/U+00A0),
  metrics, size-variant chain, delimiter table.
- `tools/gen_opclass.js` → `src/mathjax/fonts/tex_opclass.cr`
  (multi-char operator TeX classes), `tools/gen_smp.js` →
  `src/mathjax/fonts/tex_smp.cr` (math-alphanumeric variant remaps).
- `src/mathjax/svg/paths_renderer.cr` + `MathJax.to_svg(..., paths:
  true)`: a port of mathjax-full `output/common/Wrappers/*`:
  - BBox append/combine semantics (rscale, L/R), TEXSPACE matrix +
    scriptlevel>0 suppression of positive spaces, setTeXclass chain
    (fenced rows, mtr/mtd transparency, mstyle pass-through with a
    fresh inner chain, BIN demotion, autoOP);
  - mfrac/msqrt/scripts/munderover/mo geometry from the v3 wrapper
    constants (num1..denom2, sup1..sub2, texprimestyle via `Ctx.prime`,
    copySkewIC, getDelta/skew accents, big_op_spacing limits);
  - mtable per `common/Wrappers/mtable.js`: natural column widths,
    useHeight .75/.25 minimums, rowspacing/columnspacing attributes
    (parser sets them per environment, calibrated against the MathML
    oracle: matrix/array 1em+4pt, align-family 0em+3pt+displaystyle,
    cases 1em+.2em, gathered 1em+3pt), half-spacing layout, per-column
    columnalign, axis-centered bbox;
  - output-side remaps: FontData defaultMoMap/defaultAccentMap for
    single-char mo (e.g. `\vec` → U+20D7), variantForm symbols
    (`\prime` family, `\hbar`) rendered in TEX-V;
  - v3 `fixed(m,n)` number formatting (trailing-zero strip) and
    `ex()` CSS lengths (x_height = 0.442 em);
  - piecewise stretchy assembly (`addExtV`/`addExtH`, nested
    `<svg viewBox>` + scaled `<use>`) inside the root `scale(1,-1)`
    group with y-up coordinates throughout.

## Verification (acceptance gate)

`tools/render_ours.cr` + `tools/svg_diff.py` over the 1000-formula
corpus (`dataset/expected`, mathjax-full v3 SVG output):

- **96.6% of reference glyphs matched** by (face, codepoint) at the
  same position (goal was ≥ 95%);
- median position residual **13.1 units** (1000 units = 1 em) after
  centroid alignment; 775/1000 files below 100 units;
- `quadratic-formula.svg` matches byte-exactly on every glyph
  position; same for many matrix/align formulas.

Calibration helpers: `tools/render_oracle.js` (SVG via mathjax-full),
`tools/render_one.cr` (ours), `tools/tex_of.py`, `tools/dump_svg.py`,
`tools/make_reference.js` (reference MathML oracle).

## Known remaining gaps (follow-up)

- `\displaystyle\int … \left…\right` inside fraction numerators
  (wiki-0930/0937/0105 family): num/den heights still ~0.4 em short —
  stretch targets around displaystyle largeops need a closer port.
- `\big(`-style minsize handling and `\overbrace` accent semantics
  unverified against the corpus.
- menclose notation set is approximate (pad 0.2/t 0.067).
- data-mml-node/data-semantic attributes, CHTML output: out of scope.

## Original work items (all done)

1. Glyph outline tables → `tex_paths.cr` (+ empty-path glyphs).
2. Variant table (size/largeop/smallop chains, SMP remaps).
3. Stretchy delimiters: piece table + v3 assembly.
4. v3 serializer: defs/use, ex sizing, currentColor, y-up emission.
5. Corpus verification via svg_diff (numbers above).
