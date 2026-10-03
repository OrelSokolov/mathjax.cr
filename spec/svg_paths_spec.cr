# v3-structure SVG output (to_svg paths: true): the emitted SVG must
# have the MathJax v3 shape — <defs> glyph paths + <use xlink:href>,
# ex sizing, currentColor — and every glyph outline must be byte-equal
# to the reference paths from mathjax-full (Fonts::TexPaths, which is
# self-checked against dataset/expected by tools/gen_svg_fonts.py).
require "./spec_helper"

describe "SVG path output (v3 structure)" do
  it "emits defs+use with reference glyph outlines" do
    svg = MathJax.to_svg(%q(x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}),
      display: true, paths: true)

    svg.should contain %(xmlns:xlink="http://www.w3.org/1999/xlink")
    svg.should contain %(stroke="currentColor" fill="currentColor")

    # italic x -> MJX-TEX-I-1D465 outline, same d as mathjax-full
    svg.should match(/<path id="MJX-\d+-TEX-I-1D465" d="M52 289Q59 331/)
    svg.should match(/xlink:href="#MJX-\d+-TEX-I-1D465"/)

    # minus sign from the normal face
    svg.should match(/xlink:href="#MJX-\d+-TEX-N-2212"/)
    # fraction rule as a rect
    svg.should match(/<rect /)
    # root svg sized in ex with a viewBox
    svg.should match(/width="[\d.]+ex" height="[\d.]+ex"/)
    svg.should contain %(viewBox=")
  end

  it "emits the largeop face for display-style sums" do
    svg = MathJax.to_svg(%q(\sum_{i=1}^{n} i), display: true, paths: true)
    svg.should match(/xlink:href="#MJX-\d+-TEX-LO-2211"/)
  end

  it "keeps the text-based output as the default" do
    svg = MathJax.to_svg(%q(a+b))
    svg.should contain("<text")
    svg.should_not contain("<use")
  end

  it "renders a dataset sample without errors" do
    # every glyph in the quadratic-formula reference must be resolvable
    # from the generated tables
    svg = MathJax.to_svg(%q(\sum_{i=1}^{n} i = \frac{n(n+1)}{2}),
      display: true, paths: true)
    uses = svg.scan(/xlink:href="#MJX-\d+-TEX-([A-Z0-9]+)-([0-9A-Fa-f]+)"/)
    uses.size.should be > 10
    uses.each do |m|
      prefix = m[1]
      cp = m[2].to_i32(16)
      MathJax::Fonts::TexPaths::PATHS.dig?(prefix, cp).should_not be_nil
    end
  end
end
