# Simplified port of the MathJax CommonHTML output idea:
# MML tree -> nested <span>s with mjx-* classes + accompanying CSS.
# No font metrics; layout approximated with inline-block stacking.
require "../mml/node"
require "../mml/serializer"

module MathJax::Html
  module Renderer
    extend self

    CSS = <<-CSS
      .mjx-cr { display: inline-block; text-align: left; white-space: nowrap; line-height: 1.2; font-family: "Latin Modern Math", "STIX Two Math", Cambria Math, serif; }
      .mjx-cr[data-display="block"] { display: block; margin: 1em 0; text-align: center; }
      .mjx-cr i { font-style: italic; font-family: inherit; }
      .mjx-cr .mjx-mo { padding: 0 0.15em; }
      .mjx-cr .mjx-mfrac { display: inline-block; vertical-align: -0.5em; text-align: center; }
      .mjx-cr .mjx-num { display: block; padding: 0 0.2em; }
      .mjx-cr .mjx-den { display: block; border-top: 1px solid currentColor; padding: 0 0.2em; }
      .mjx-cr .mjx-sub { display: inline-block; vertical-align: -0.35em; font-size: 0.7em; }
      .mjx-cr .mjx-sup { display: inline-block; vertical-align: 0.65em; font-size: 0.7em; }
      .mjx-cr .mjx-sub .mjx-sup, .mjx-cr .mjx-sup .mjx-sub { font-size: 1em; }
      .mjx-cr .mjx-under { display: inline-block; vertical-align: 0.5em; font-size: 0.7em; }
      .mjx-cr .mjx-over { display: inline-block; vertical-align: -0.5em; font-size: 0.7em; }
      .mjx-cr .mjx-under, .mjx-cr .mjx-over { text-align: center; }
      .mjx-cr .mjx-under-over { display: inline-block; vertical-align: middle; text-align: center; }
      .mjx-cr .mjx-under-over > .mjx-base { display: block; }
      .mjx-cr .mjx-under-over > .mjx-under { vertical-align: 0; display: block; }
      .mjx-cr .mjx-under-over > .mjx-over { vertical-align: 0; display: block; }
      .mjx-cr .mjx-sqrt { display: inline-block; border-top: 1px solid currentColor; padding-left: 0.3em; }
      .mjx-cr .mjx-radical { display: inline-block; vertical-align: bottom; margin-right: -0.1em; }
      .mjx-cr .mjx-table { display: inline-table; vertical-align: middle; border-collapse: collapse; }
      .mjx-cr .mjx-row { display: table-row; }
      .mjx-cr .mjx-cell { display: table-cell; padding: 0 0.3em; text-align: center; }
      .mjx-cr .mjx-mtext { font-style: normal; }
      .mjx-cr .mjx-merror { color: #c00; border: 1px solid #c00; padding: 0 0.2em; }
      .mjx-cr .mjx-bold { font-weight: bold; font-style: normal; }
      .mjx-cr .mjx-upright { font-style: normal; }
      .mjx-cr .mjx-frak { font-family: "Fraktur Unicode", serif; }
      .mjx-cr .mjx-monospace { font-family: monospace; }
      .mjx-cr .mjx-sans { font-family: sans-serif; }
      .mjx-cr .mjx-double { font-family: "Double-struck Unicode", serif; }
    CSS

    def escape(text : String) : String
      Mml::Serializer.escape(text)
    end

    def call(node : Mml::Node) : String
      inner = String.build { |io| render_children(io, node) }
      String.build do |io|
        io << %(<span class="mjx-cr")
        io << %( data-display="block") if node["display"] == "block"
        io << ">"
        io << inner
        io << "</span>"
      end
    end

    private def render_children(io : IO, node : Mml::Node) : Nil
      if text = node.text
        io << escape(text)
        return
      end
      node.children.each { |child| render(io, child) }
    end

    private def font_class(node : Mml::Node) : String?
      case node["mathvariant"]?
      when "bold" then "mjx-bold"
      when "fraktur" then "mjx-frak"
      when "monospace" then "mjx-monospace"
      when "sans-serif" then "mjx-sans"
      when "double-struck" then "mjx-double"
      when "normal" then "mjx-upright"
      else nil
      end
    end

    private def render(io : IO, node : Mml::Node) : Nil
      case node.kind
      when "mi"
        io << %(<i)
        io << %( class=") << font_class(node) << %(") if font_class(node)
        io << ">" << escape(node.text.to_s) << "</i>"
      when "mn"
        io << escape(node.text.to_s)
      when "mo"
        io << %(<span class="mjx-mo">) << escape(node.text.to_s) << "</span>"
      when "mtext"
        io << %(<span class="mjx-mtext">) << escape(node.text.to_s) << "</span>"
      when "merror"
        io << %(<span class="mjx-merror">)
        render_children(io, node)
        io << "</span>"
      when "mspace"
        width = node["width"]?.try &.gsub("em", "em")
        io << %(<span style="display:inline-block;width:) << escape(width || "0") << %("></span>)
      when "mfrac"
        num, den = node.children
        io << %(<span class="mjx-mfrac"><span class="mjx-num">)
        render(io, num)
        io << %(</span><span class="mjx-den">)
        render(io, den)
        io << "</span></span>"
      when "msub", "msup"
        base, script = node.children
        cls = node.kind == "msub" ? "mjx-sub" : "mjx-sup"
        render(io, base)
        io << %(<span class=") << cls << %(">)
        render(io, script)
        io << "</span>"
      when "msubsup"
        base, sub, sup = node.children
        render(io, base)
        io << %(<span class="mjx-sub"><span class="mjx-sup">)
        render(io, sup)
        io << %(</span>)
        render(io, sub)
        io << "</span>"
      when "munder", "mover"
        base, script = node.children
        top = node.kind == "munder" ? base : script
        bottom = node.kind == "munder" ? script : base
        io << %(<span style="display:inline-block;vertical-align:middle;text-align:center">)
        io << %(<span class="mjx-base">)
        render(io, top)
        io << %(</span><span class=")
        io << (node.kind == "munder" ? "mjx-under" : "mjx-over") << %(">)
        render(io, bottom)
        io << "</span></span>"
      when "munderover"
        base, under, over = node.children
        io << %(<span class="mjx-under-over">)
        io << %(<span class="mjx-over">); render(io, over); io << "</span>"
        io << %(<span class="mjx-base">); render(io, base); io << "</span>"
        io << %(<span class="mjx-under">); render(io, under); io << "</span>"
        io << "</span>"
      when "msqrt"
        io << %(<span class="mjx-radical">√</span><span class="mjx-sqrt">)
        node.children.each { |c| render(io, c) }
        io << "</span>"
      when "mroot"
        base, index = node.children
        io << %(<span class="mjx-sup">); render(io, index); io << "</span>"
        io << %(<span class="mjx-radical">√</span><span class="mjx-sqrt">)
        render(io, base)
        io << "</span>"
      when "mtable"
        io << %(<span class="mjx-table">)
        node.children.each do |row|
          io << %(<span class="mjx-row">)
          row.children.each do |cell|
            io << %(<span class="mjx-cell">)
            cell.children.each { |c| render(io, c) }
            io << "</span>"
          end
          io << "</span>"
        end
        io << "</span>"
      when "mstyle", "mrow", "mphantom", "menclose", "math"
        io << %(<span class="mjx-) << node.kind << %(">)
        io << %(<span class=") << font_class(node) << %(">) if font_class(node)
        render_children(io, node)
        io << "</span>" if font_class(node)
        io << "</span>"
      else
        render_children(io, node)
      end
    end
  end
end
