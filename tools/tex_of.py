#!/usr/bin/env python3
import re, sys
s = open('dataset/manifest.json').read()
for id in sys.argv[1:]:
    m = re.search(r'\{\s*"id":\s*"%s".*?"tex":\s*"((?:[^"\\]|\\.)*)"' % id, s, re.S)
    print(id, '::', m.group(1)[:400] if m else None)
