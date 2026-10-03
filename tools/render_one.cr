# Render one TeX string with our paths renderer and print glyph uses.
#   crystal run tools/render_one.cr -- '\tex' [display]
require "../src/mathjax"
tex = ARGV[0]
display = ARGV[1]? == "display"
svg = MathJax.to_svg(tex, display: display, paths: true)
File.write("/tmp/one_ours.svg", svg)
puts svg
