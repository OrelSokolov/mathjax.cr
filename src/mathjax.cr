# mathjax.cr — Crystal port of the MathJax core.
# TeX / AsciiMath / MathML input -> MML tree -> MathML / HTML / SVG output.
require "./mathjax/mml/node"
require "./mathjax/mml/serializer"
require "./mathjax/mml/mathml_parser"
require "./mathjax/fonts/tex_metrics"
require "./mathjax/tex/symbols"
require "./mathjax/tex/parser"
require "./mathjax/asciimath/parser"
require "./mathjax/html/renderer"
require "./mathjax/svg/renderer"
require "./mathjax/svg/paths_renderer"
require "./mathjax/fonts/tex_paths"

module MathJax
  VERSION = "1.1.0"

  # Parse a TeX expression into an MML tree (<math> root).
  # Raises `TeX::TexError` on invalid input.
  # `physics: true` enables the physics macro subset.
  def self.parse(tex : String, display : Bool = false, physics : Bool = false) : Mml::Node
    TeX::Parser.new(tex, display, physics: physics).parse
  end

  # Parse an AsciiMath expression into an MML tree (subset).
  def self.parse_asciimath(input : String, display : Bool = false) : Mml::Node
    AsciiMath::Parser.parse(input, display)
  end

  # Parse a MathML string into an MML tree.
  def self.from_mathml(mathml : String) : Mml::Node
    Mml::MathmlParser.call(mathml)
  end

  # TeX -> MathML string.
  def self.to_mathml(tex : String, display : Bool = false, physics : Bool = false) : String
    Mml::Serializer.call(parse(tex, display, physics: physics))
  end

  # TeX -> HTML string (spans with mjx-* classes; see `.css`).
  def self.to_html(tex : String, display : Bool = false, physics : Bool = false) : String
    Html::Renderer.call(parse(tex, display, physics: physics))
  end

  # TeX -> SVG string (metrics-based layout, see `MathJax::Fonts`).
  # With `paths: true`, emits the MathJax v3 structure instead: glyph
  # outline paths in a single <defs> + <use xlink:href>, sized in ex,
  # colored via currentColor — rasterizes by nanosvg.cr without
  # system fonts.
  def self.to_svg(tex : String, display : Bool = false, physics : Bool = false,
                  paths : Bool = false) : String
    node = parse(tex, display, physics: physics)
    if paths
      Svg::PathsRenderer.call(node, display)
    else
      Svg::Renderer.call(node, display)
    end
  end

  # CSS for the HTML output.
  def self.css : String
    Html::Renderer::CSS
  end

  # Parse and return an <merror> node instead of raising.
  def self.parse_or_error(tex : String, display : Bool = false) : Mml::Node
    parse(tex, display)
  rescue e : TeX::TexError
    err = Mml::Node.new("math").add(Mml::Node.leaf("merror", e.message.to_s))
    err.set("display", "block") if display
    err
  end
end
