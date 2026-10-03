# mathjax.cr

[English version](README.md)

Порт ядра [MathJax](https://github.com/mathjax/MathJax) (v3) на Crystal:
**TeX / AsciiMath / MathML → внутреннее MML-дерево → MathML / HTML / SVG**.

Портировано (по мотивам исходников `ts/` из
[mathjax-src](https://github.com/mathjax/mathjax-src) и данных шрифтов
MathJax v2):

## Входы

- **TeX-парсер** (`input/tex`): токенизатор, группы `{...}`, скрипты `^`/`_`,
  штрихи `'`, `\frac`-семейство, обобщённые дроби (`a \over b`, `\atop`,
  `\choose`, `\above`, `\genfrac`), `\sqrt`/`\root`, `\left...\right` с
  `\middle`, окружения (`matrix/pmatrix/bmatrix/vmatrix/Vmatrix/cases/array/
  aligned/...`), шрифты (`\mathrm`, `\mathbf`, `\mathbb`, ...), акценты
  (`\vec`, `\hat`, `\overline`, `\overrightarrow`, ...), пробелы, `\text`,
  `\stackrel`, `\overbrace`/`\underbrace`, `\phantom`, `\boxed`, большие
  операторы с пределами (`munderover`, `\limits`/`\nolimits`), макросы
  `\def`/`\newcommand` (с `#1..#9`).
- **Расширения**: `color` (`\color`, `\textcolor`, `\definecolor` с моделями
  rgb/RGB/gray/HTML/cmyk, `\colorbox`, `\fcolorbox`), `cancel`
  (`\cancel`, `\bcancel`, `\xcancel`, `\sout`), подмножество `physics`
  (`\abs`, `\norm`, `\dv`, `\pdv`, `\dd`, `\bra`, `\ket`, `\braket`, `\mel`,
  `\comm`, ... — включается через `physics: true` / `--physics`).
- **AsciiMath** (подмножество `input/asciimath`): дроби `a/b`, `^`/`_`,
  греческие имена, `sum/prod/int` с пределами, отношения и стрелки
  (`<= >= != -> => <=>`), `sqrt`, `hat/bar/vec/ul(...)`, `|x|`, `floor/ceil`,
  матрицы `[[a,b],[c,d]]`, текст `"..."`.
- **MathML-вход** (`input/mml`): XML → дерево (round-trip с сериализатором).

## Выходы

- **MathML** — сериализация дерева.
- **HTML** — упрощённый аналог CommonHTML: spans + CSS (`MathJax.css`).
- **SVG** — типографика по настоящим метрикам TeX-шрифта: таблица глифов
  (ширина/высота/глубина в em) портирована из данных шрифтов MathJax
  (`MathJax::Fonts`, Main/Math/Size1–4, ~900 глифов).

## Не портировано

a11y (SRE — отдельная большая система), CHTML/SVG с глиф-путями шрифтов
(SVG использует `<text>` и системные шрифты), расширения `action`,
`autobold`, `bbox`, `bussproofs`, `cancel` с опциями цвета, `centernot`,
`colortbl`, `empheq`, `extpfeil`, `gensymb`, `html`, `mathtools`,
`mhchem`, `newcommand`-условия, `noerrors`-конфигурации, `upgreek`,
`verb` и полная таблица AMS (покрыто ~180 базовых команд).

## Установка

```yaml
dependencies:
  mathjax:
    git: https://github.com/OrelSokolov/mathjax.cr
```

## Использование

```crystal
require "mathjax"

MathJax.to_mathml("\\frac{1}{2}")                   # MathML
MathJax.to_mathml("x^2", display: true)
MathJax.to_html("\\sqrt{2}")                        # HTML + классы mjx-*
MathJax.to_svg("\\frac{a+b}{c}")                    # SVG с метриками TeX
MathJax.css                                         # CSS для HTML-вывода
MathJax.parse("\\sum_{i=1}^n i")                    # => MathJax::Mml::Node
MathJax.to_mathml("\\abs{x}", physics: true)        # расширение physics
MathJax::Mml::Serializer.call(
  MathJax.parse_asciimath("sum_(i=1)^n i"))         # AsciiMath-вход
MathJax.from_mathml("<math>...</math>")             # MathML-вход
MathJax::Fonts.width('a', "math_italic")            # 0.529 (метрики TeX)
```

Ошибки разбора: `MathJax::TeX::TexError`, `MathJax::AsciiMath::AsciiMathError`,
`MathJax::Mml::MathmlError`.

## CLI

```sh
crystal run src/cli.cr -- --html --display < formula.tex
crystal run src/cli.cr -- --svg < formula.tex
crystal run src/cli.cr -- --physics --mml <<< '\dv{f}{x}'
crystal run src/cli.cr -- --ascii --mml <<< 'sum_(i=1)^n i'
echo '\frac{-b\pm\sqrt{b^2-4ac}}{2a}' | crystal run src/cli.cr
```

## Тесты

```sh
crystal spec   # 83 примера, включая пороги датасета
```

## Интеграционное тестирование (1-в-1 с MathJax)

1000 TeX-формул из англоязычной Википедии прогоняются через `mathjax.cr`
и через настоящий MathJax (`mathjax-full`), MathML-деревья сравниваются
после нормализации (см. `test/datasets/REPORT.md`):

- разобрано **99.3%** формул (993/1000);
- **99.1%** структурно идентичных деревьев (990/999 comparable).

```sh
crystal run tools/compare.cr        # полный отчёт + diffs.txt
crystal run tools/dump_one.cr -- 91 # деревья ours vs ref для формулы #91
```

Датасет и эталон пересобираются: `tools/fetch_formulas.cr` (Wikipedia API)
и `tools/make_reference.js` (node + mathjax-full).

## Структура

```
src/mathjax.cr                 публичный API
src/mathjax/tex/{parser,symbols}.cr     TeX-вход (порт input/tex)
src/mathjax/asciimath/parser.cr         AsciiMath-вход
src/mathjax/mml/                         MML-дерево, сериализатор, MathML-вход
src/mathjax/html/renderer.cr            HTML-вывод
src/mathjax/svg/renderer.cr             SVG-вывод (метрики)
src/mathjax/fonts/tex_metrics.cr        таблица глифов TeX-шрифта (генерируется)
vendor/                                  исходники MathJax (для справки)
```

## Лицензия

Apache-2.0 (как и сам MathJax). `mathjax.cr` — самостоятельная реализация
на Crystal; метрики шрифта взяты из данных MathJax (Apache-2.0).
