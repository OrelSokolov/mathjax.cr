# Golden dataset (TeX → SVG)

[Русская версия](README.ru.md)

1000 formulas for comparing the `mathjax.cr` SVG output against the
oracle — **the original MathJax v3**.

Composition:

- **40 curated** well-known formulas (the quadratic formula, Euler's
  identity, the Fourier transform, the Schrödinger equation, ...) — the
  `source` fields point to the Wikipedia articles they come from.
- **960 real** formulas extracted from `<math>` tags of Wikipedia articles
  (categories Calculus, Linear algebra, Probability theory, ...), at most
  15 formulas per article (96 articles). Only formulas that the current
  `mathjax.cr` TeX parser handles without errors were accepted.

## Layout

```
dataset/
  manifest.json        # single source of truth: id, title, source, tex, display
  inputs/<id>.tex      # TeX inputs (generated from the manifest)
  expected/<id>.svg    # reference SVGs (original MathJax v3, fontCache: local)
  oracle/              # generation scripts + a local mathjax-full
    fetch_wiki.py      # top up the manifest with Wikipedia formulas (up to TARGET)
    render.js          # regenerate inputs/ and expected/ from the manifest
    mathjax-cli        # built mathjax.cr CLI (used for the parser filter)
```

Every SVG is self-contained (glyphs embedded via `fontCache: 'local'`),
valid XML and **pure `<svg>`** — the `<mjx-container>` wrapper emitted by
`mathjax-full` is stripped (`TeX → SVG`, liteAdaptor, `em: 16`,
`containerWidth: 80em`). `display: true` in the manifest means block mode
(95 cases), `false` — inline (905, as in the Wikipedia articles
themselves).

## Regeneration

```sh
# 1. build the CLI (used by the "parser accepts it" filter)
crystal build -o dataset/oracle/mathjax-cli src/cli.cr

# 2. top up formulas from Wikipedia up to 1000 cases (idempotent:
#    wiki-* cases are recreated, curated ones stay)
python3 dataset/oracle/fetch_wiki.py

# 3. regenerate inputs/ and expected/ (full rewrite)
cd dataset/oracle && npm install && node render.js
```

The manifest is the source of truth: files in `inputs/` and `expected/`
are never edited by hand, only regenerated. `node_modules`, `mathjax-cli`
and `package-lock.json` are gitignored.

The fetching script respects Wikipedia API limits: ~0.8 s/request
throttling, `Retry-After` backoff on HTTP 429.
