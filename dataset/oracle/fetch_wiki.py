#!/usr/bin/env python3
"""Extend dataset/manifest.json to the target case count with real
<formula> tags scraped from Wikipedia articles (math-related categories).

Pipeline: category members -> wikitext (batched API) -> <math> extraction
-> cleanup/dedupe -> keep only formulas that mathjax.cr parses (exit 0
from dataset/oracle/mathjax-cli) -> append as wiki-NNNN cases.

Run from anywhere:
    crystal build -o dataset/oracle/mathjax-cli src/cli.cr
    python3 dataset/oracle/fetch_wiki.py
"""
import html
import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://en.wikipedia.org/w/api.php"
UA = "mathjax.cr-dataset-builder/0.1 (dataset for TeX->SVG oracle tests)"
TARGET = 1000
MAX_PAGES = 1500          # stop scraping after this many articles
MAX_FORMULA_LEN = 400     # skip monster formulas
MAX_PER_ARTICLE = 15      # diversity: formulas kept per single article
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CLI = os.path.join(HERE, "mathjax-cli")
MANIFEST = os.path.join(ROOT, "manifest.json")

CATEGORIES = [
    "Category:Calculus",
    "Category:Linear algebra",
    "Category:Probability theory",
    "Category:Statistics",
    "Category:Geometry",
    "Category:Number theory",
    "Category:Trigonometry",
    "Category:Mathematical analysis",
    "Category:Abstract algebra",
    "Category:Differential equations",
    "Category:Equations",
    "Category:Physics equations",
    "Category:Mathematical physics",
    "Category:Mathematical optimization",
    "Category:Combinatorics",
]

MATH_RE = re.compile(r"<math([^>]*)>(.*?)</math>", re.S)
DISPLAY_RE = re.compile(r'display\s*=\s*"block"')

MIN_INTERVAL = 0.8  # seconds between API requests
_last_request = [0.0]


def api(params):
    qs = urllib.parse.urlencode(params)
    url = f"{API}?{qs}"
    for attempt in range(6):
        delay = MIN_INTERVAL - (time.monotonic() - _last_request[0])
        if delay > 0:
            time.sleep(delay)
        _last_request[0] = time.monotonic()
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 5:
                raise
            wait = e.headers.get("Retry-After") or ""
            wait = int(wait) if wait.isdigit() else 5 * 2 ** attempt
            print(f"  429: backing off {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def category_members(cat, cmtype):
    """All titles of a given member type for a category, following continuation."""
    out, cont = [], None
    while True:
        p = {"action": "query", "list": "categorymembers", "cmtitle": cat,
             "cmtype": cmtype, "cmlimit": 500, "format": "json"}
        if cont:
            p["cmcontinue"] = cont
        d = api(p)
        out += [m["title"] for m in d["query"]["categorymembers"]]
        cont = d.get("continue", {}).get("cmcontinue")
        if not cont:
            return out


def collect_articles():
    articles = set()
    for cat in CATEGORIES:
        try:
            pages = set(category_members(cat, "page"))
            subcats = category_members(cat, "subcat")
        except Exception as e:
            print(f"  warn: {cat}: {e}", file=sys.stderr)
            continue
        articles |= {t for t in pages if not t.startswith(("List of", "Glossary of", "Outline of"))}
        for sub in subcats[:8]:  # cap subcategory requests per category
            try:
                articles |= {t for t in category_members(sub, "page")
                             if not t.startswith(("List of", "Glossary of", "Outline of"))}
            except Exception as e:
                print(f"  warn: {sub}: {e}", file=sys.stderr)
        print(f"{cat}: {len(articles)} articles so far", file=sys.stderr)
        if len(articles) >= MAX_PAGES:
            break
    articles = sorted(articles)
    random.Random(42).shuffle(articles)
    return articles[:MAX_PAGES]


def wikitexts(titles):
    """Yield (title, wikitext) for titles, in batches of 50."""
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        cont = None
        while True:
            p = {"action": "query", "prop": "revisions", "rvprop": "content",
                 "rvslots": "main", "format": "json",
                 "titles": "|".join(batch)}
            if cont:
                p["rvcontinue"] = cont
            d = api(p)
            for page in d["query"]["pages"].values():
                if "revisions" not in page:
                    continue
                yield page["title"], page["revisions"][0]["slots"]["main"]["*"]
            cont = d.get("continue", {}).get("rvcontinue")
            if not cont:
                break


def extract_math(wikitext):
    for m in MATH_RE.finditer(wikitext):
        attrs, body = m.group(1), m.group(2)
        tex = " ".join(html.unescape(body).split())
        if not (3 <= len(tex) <= MAX_FORMULA_LEN):
            continue
        yield tex, bool(DISPLAY_RE.search(attrs))


def parses_ok(tex):
    r = subprocess.run([CLI], input=tex.encode(), capture_output=True)
    return r.returncode == 0


def main():
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    # idempotent: rebuild on top of the curated cases only
    cases = [c for c in manifest["cases"] if not c["id"].startswith("wiki-")]
    manifest["cases"] = cases
    need = TARGET - len(cases)
    if need <= 0:
        print(f"manifest already has {len(cases)} cases, nothing to do")
        return

    seen = {c["tex"] for c in cases}
    articles = collect_articles()
    print(f"scraping {len(articles)} articles for {need} formulas", file=sys.stderr)

    wiki_cases, accepted, tried, processed = [], 0, 0, 0
    for title, text in wikitexts(articles):
        processed += 1
        taken_from_article = 0
        for tex, display in extract_math(text):
            if tex in seen:
                continue
            seen.add(tex)
            tried += 1
            if taken_from_article >= MAX_PER_ARTICLE or not parses_ok(tex):
                continue
            wiki_cases.append({"id": f"wiki-{accepted:04d}", "title": title,
                               "source": title, "tex": tex, "display": display})
            accepted += 1
            taken_from_article += 1
            if accepted >= need:
                break
        if accepted >= need:
            break
        if processed % 100 == 0:
            print(f"  {processed} articles, {tried} unique formulas, "
                  f"{accepted} accepted", file=sys.stderr)

    if accepted < need:
        print(f"error: only {accepted}/{need} formulas accepted "
              f"(from {processed} articles); widen CATEGORIES or raise MAX_PAGES",
              file=sys.stderr)
        sys.exit(1)

    cases += wiki_cases
    json.dump(manifest, open(MANIFEST, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"manifest now has {len(cases)} cases "
          f"(+{accepted} from Wikipedia, acceptance {accepted}/{tried})")


if __name__ == "__main__":
    main()
