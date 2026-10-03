# Golden dataset (TeX → SVG)

1000 формул для сравнения SVG-вывода `mathjax.cr` с оракулом —
**оригинальным MathJax v3**.

Состав:

- **40 курируемых** распространённых формул (квадратная формула, тождество
  Эйлера, преобразование Фурье, уравнение Шрёдингера, ...) — поля `source`
  указывают статьи Википедии, откуда они взяты.
- **960 реальных** формул, извлечённых из `<math>`-тегов статей Википедии
  (категории Calculus, Linear algebra, Probability theory, ...), по
  максимум 15 формул из одной статьи (96 статей). Принимались только те,
  которые текущий TeX-парсер `mathjax.cr` разбирает без ошибок.

## Структура

```
dataset/
  manifest.json        # единый источник правды: id, title, source, tex, display
  inputs/<id>.tex      # TeX-инпуты (сгенерированы из манифеста)
  expected/<id>.svg    # эталонные SVG (оригинальный MathJax v3, fontCache: local)
  oracle/              # скрипты генерации + локальный mathjax-full
    fetch_wiki.py      # дополнить манифест формулами из Википедии (до TARGET)
    render.js          # перегенерировать inputs/ и expected/ из манифеста
    mathjax-cli        # собранный CLI mathjax.cr (для фильтра парсером)
```

Каждый SVG самодостаточен (глифы встроены через `fontCache: 'local'`),
валиден как XML и обёрнут в `<mjx-container jax="SVG">`, как выдаёт
`mathjax-full` (`TeX → SVG`, liteAdaptor, `em: 16`, `containerWidth: 80em`).
`display: true` в манифесте — блочный режим (95 случаев), `false` — inline
(905, как в самих статьях Википедии).

## Регенерация

```sh
# 1. собрать CLI (используется фильтром «парсер это принимает»)
crystal build -o dataset/oracle/mathjax-cli src/cli.cr

# 2. добрать формулы из Википедии до 1000 кейсов (идемпотентно:
#    wiki-* кейсы пересоздаются, курируемые остаются)
python3 dataset/oracle/fetch_wiki.py

# 3. перегенерировать inputs/ и expected/ (полная перезапись)
cd dataset/oracle && npm install && node render.js
```

Манифест — источник правды: файлы в `inputs/` и `expected/` не правятся
руками, а только перегенерируются. `node_modules`, `mathjax-cli` и
`package-lock.json` в `.gitignore`.

Скрипт загрузки уважает лимиты API Википедии: троттлинг ~0.8 с/запрос,
backoff по `Retry-After` на HTTP 429.
