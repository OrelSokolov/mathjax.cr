# SVG output: metrics-based typesetting using the TeX font data
# (MathJax::Fonts, ported from MathJax font metrics).
# A simplified analogue of MathJax's SVG output: <text> glyphs laid out at
# computed positions instead of font glyph paths.
require "../mml/node"
require "../fonts/tex_metrics"

module MathJax::Svg
  class Renderer
    # All layout in em units (x right, y DOWN like SVG). Ex: baseline y=0.
    record Box, width : Float64, ascent : Float64, descent : Float64 do
      def height
        ascent + descent
      end
    end

    property display : Bool

    def initialize(@display : Bool = false)
    end

    def self.call(node : Mml::Node, display : Bool = false) : String
      new(display).render(node)
    end

    def render(node : Mml::Node) : String
      children = node.children
      if children.size == 1
        box = measure(children.first)
        draw_root(children.first, box)
      else
        box = measure_list(children)
        draw_root_list(children, box)
      end
    end

    private def draw_root(node : Mml::Node, box : Box) : String
      String.build do |io|
        header(io, box)
        draw(io, node, 0.0, 0.0, 1.0)
        footer(io)
      end
    end

    private def draw_root_list(nodes : Array(Mml::Node), box : Box) : String
      String.build do |io|
        header(io, box)
        x = 0.0
        nodes.each do |n|
          b = measure(n)
          draw(io, n, x, 0.0, 1.0)
          x += b.width + 0.15
        end
        footer(io)
      end
    end

    private def header(io : IO, box : Box) : Nil
      pad = 0.1
      w = ((box.width + 2 * pad) * 1000).round.to_i
      y0 = ((box.ascent + pad) * 1000).round.to_i
      h = ((box.height + 2 * pad) * 1000).round.to_i
      io << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}")
      io << %( style="vertical-align: #{-(y0 - 1000)}px") if y0 != 1000
      io << %(>\n<g transform="translate(#{(pad * 1000).round.to_i},#{y0})" font-family="serif">)
    end

    private def footer(io : IO) : Nil
      io << "\n</g>\n</svg>"
    end

    # ------------------------------------------------------------------
    # Measuring

    protected def variant_of(node : Mml::Node) : String
      case node["mathvariant"]?
      when "bold" then "main_bold"
      else
        case node.kind
        when "mi" then "math_italic"
        else "main"
        end
      end
    end

    protected def measure(node : Mml::Node) : Box
      case node.kind
      when "mi", "mn", "mo", "mtext", "ms"
        measure_text(node.text.to_s, variant_of(node))
      when "mrow", "math", "mstyle", "merror", "mphantom", "menclose"
        measure_list(node.children)
      when "mspace"
        w = (node["width"]? || "0").gsub("em", "").to_f? || 0.0
        Box.new(w, 0.0, 0.0)
      when "mfrac"
        num, den = node.children
        nb = measure(num)
        db = measure(den)
        w = {nb.width, db.width}.max + 0.4
        rule = 0.06
        Box.new(w, nb.height + rule / 2 + 0.25, db.height + rule / 2 + 0.25)
      when "msub", "msup", "msubsup", "munder", "mover", "munderover"
        measure_scripts(node)
      when "msqrt", "mroot"
        content = node.kind == "msqrt" ? node.children : [node.children.first]
        cb = measure_list(content)
        Box.new(cb.width + cb.height * 0.65 + 0.1, cb.ascent + 0.1, cb.descent)
      when "mtable"
        measure_table(node)
      else
        measure_list(node.children)
      end
    end

    protected def measure_text(text : String, variant : String) : Box
      chars = text.chars
      return Box.new(0.0, 0.0, 0.0) if chars.empty? # e.g. empty <mi/> placeholders
      width = chars.sum { |c| Fonts.width(c, variant) }
      ascent = chars.max_of { |c| Fonts.height(c, variant) }
      descent = chars.max_of { |c| Fonts.depth(c, variant) }
      Box.new(width + 0.05, ascent, descent)
    end

    protected def measure_list(nodes : Array(Mml::Node)) : Box
      return Box.new(0.0, 0.5, 0.2) if nodes.empty?
      width = 0.0
      ascent = 0.5
      descent = 0.2
      nodes.each_with_index do |n, i|
        b = measure(n)
        width += b.width
        width += 0.15 if i > 0
        ascent = {ascent, b.ascent}.max
        descent = {descent, b.descent}.max
      end
      Box.new(width, ascent, descent)
    end

    protected def measure_scripts(node : Mml::Node) : Box
      base = measure(node.children.first)
      if node.kind.in?("msub", "msup", "msubsup")
        script_scale = 0.7
        if node.kind == "msub"
          s = measure(node.children[1])
          Box.new(base.width + s.width * script_scale, base.ascent,
            base.descent + s.height * script_scale)
        elsif node.kind == "msup"
          s = measure(node.children[1])
          Box.new(base.width + s.width * script_scale, base.ascent + s.height * script_scale,
            base.descent)
        else
          sub = measure(node.children[1])
          sup = measure(node.children[2])
          Box.new(base.width + {sub.width, sup.width}.max * script_scale,
            base.ascent + sup.height * script_scale,
            base.descent + sub.height * script_scale)
        end
      else # munder / mover / munderover
        under = node.kind == "munder" ? measure(node.children[1]) : (node.kind == "mover" ? measure(node.children[1]) : measure(node.children[1]))
        over = node.kind == "munderover" ? measure(node.children[2]) : nil
        w = {base.width, under.width, over.try(&.width) || 0.0}.max
        ascent = base.ascent + (over.try(&.height) || 0.0)
        descent = base.descent + under.height
        Box.new(w, ascent, descent)
      end
    end

    protected def measure_table(node : Mml::Node) : Box
      rows = node.children
      widths = column_widths(node)
      width = widths.sum + 0.3
      height = rows.sum { |r| row_height(r) } + 0.2 * (rows.size - 1)
      Box.new(width, height * 0.55, height * 0.45)
    end

    protected def column_widths(table : Mml::Node) : Array(Float64)
      ncols = table.children.max_of(&.children.size)
      Array.new(ncols, 0.0).tap do |widths|
        table.children.each do |row|
          row.children.each_with_index do |cell, i|
            b = measure_list(cell.children)
            widths[i] = {widths[i], b.width}.max
          end
        end
      end
    end

    protected def row_height(row : Mml::Node) : Float64
      row.children.max_of { |c| measure_list(c.children).height } * 1.1
    end

    # ------------------------------------------------------------------
    # Drawing

    private def draw(io : IO, node : Mml::Node, x : Float64, y : Float64, scale : Float64) : Nil
      case node.kind
      when "mi", "mn", "mo", "mtext", "ms"
        io << %(<text x="#{fmt(x)}" y="#{fmt(y)}" font-size="#{fmt(scale)}px")
        io << %( font-style="italic") if node.kind == "mi" && node["mathvariant"]? != "normal"
        io << %( font-weight="bold") if variant_of(node) == "main_bold"
        io << ">"
        io << Mml::Serializer.escape(node.text.to_s)
        io << "</text>"
      when "mrow", "math", "mstyle", "merror", "mphantom", "menclose"
        draw_list(io, node.children, x, y, scale)
      when "mspace"
        # spaces draw nothing
      when "mfrac"
        num, den = node.children
        nb = measure(num)
        db = measure(den)
        w = {nb.width, db.width}.max + 0.4
        cx = x + w / 2
        rule = 0.04
        draw(io, num, cx - nb.width / 2, y - 0.25 - rule / 2, scale)
        draw(io, den, cx - db.width / 2, y + 0.25 + rule / 2 + db.ascent, scale)
        io << %(<line x1=") << fmt(x + 0.2) << %(" y1=") << fmt(y)
        io << %(" x2=") << fmt(x + w - 0.2) << %(" y2=") << fmt(y)
        io << %(" stroke="currentColor" stroke-width=") << fmt(0.05) << %("/>)
      when "msub", "msup", "msubsup"
        base = measure(node.children.first)
        ss = 0.7 * scale
        case node.kind
        when "msub"
          draw(io, node.children[1], x + base.width + 0.02, y + 0.2, ss)
        when "msup"
          draw(io, node.children[1], x + base.width + 0.02, y - 0.45, ss)
        else
          draw(io, node.children[1], x + base.width + 0.02, y + 0.2, ss)
          draw(io, node.children[2], x + base.width + 0.02, y - 0.45, ss)
        end
        draw(io, node.children.first, x, y, scale)
      when "munder", "mover", "munderover"
        base = measure(node.children.first)
        if node.kind == "munderover"
          under = measure(node.children[1])
          over = measure(node.children[2])
          draw(io, node.children.first, x, y, scale)
          draw(io, node.children[1], x + (base.width - under.width) / 2, y + base.descent + 0.1 + under.ascent, 0.7 * scale)
          draw(io, node.children[2], x + (base.width - over.width) / 2, y - base.ascent - 0.1, 0.7 * scale)
        else
          script = node.children[1]
          sb = measure(script)
          draw(io, node.children.first, x, y, scale)
          if node.kind == "munder"
            draw(io, script, x + (base.width - sb.width) / 2, y + base.descent + 0.1 + sb.ascent, 0.7 * scale)
          else
            draw(io, script, x + (base.width - sb.width) / 2, y - base.ascent - 0.1, 0.7 * scale)
          end
        end
      when "msqrt", "mroot"
        content = node.kind == "msqrt" ? node.children : [node.children.first]
        cb = measure_list(content)
        h = cb.height
        # radical sign drawn as a polyline sized to content height
        rw = h * 0.6
        sign = [0.05, 0.3, 0.5, 0.05, 0.3].sum { |_f| 0.0 } # placeholder for width calc
        io << %(<path d="M ) << fmt(x + rw * 0.1) << " " << fmt(y - h * 0.45)
        io << " L " << fmt(x + rw * 0.4) << " " << fmt(y + h * 0.55)
        io << " L " << fmt(x + rw * 0.75) << " " << fmt(y - h * 0.5)
        io << %( L ) << fmt(x + rw) << " " << fmt(y - h * 0.5)
        io << %(" fill="none" stroke="currentColor" stroke-width=") << fmt(0.05) << %("/>)
        draw_list(io, content, x + rw + 0.08, y, scale)
        io << %(<line x1=") << fmt(x + rw + 0.02) << %(" y1=") << fmt(y - h * 0.5)
        io << %(" x2=") << fmt(x + rw + 0.08 + cb.width) << %(" y2=") << fmt(y - h * 0.5)
        io << %(" stroke="currentColor" stroke-width=") << fmt(0.05) << %("/>)
        if node.kind == "mroot"
          idx = node.children[1]
          draw(io, idx, x, y - h * 0.5 - 0.15, 0.6 * scale)
        end
      when "mtable"
        draw_table(io, node, x, y, scale)
      else
        draw_list(io, node.children, x, y, scale)
      end
    end

    private def draw_list(io : IO, nodes : Array(Mml::Node), x : Float64, y : Float64, scale : Float64) : Nil
      cx = x
      nodes.each_with_index do |n, i|
        b = measure(n)
        draw(io, n, cx, y, scale)
        cx += b.width + (i < nodes.size - 1 ? 0.15 : 0.0)
      end
    end

    private def draw_table(io : IO, table : Mml::Node, x : Float64, y : Float64, scale : Float64) : Nil
      widths = column_widths(table)
      row_h = table.children.map { |r| row_height(r) }
      total_h = row_h.sum + 0.2 * (row_h.size - 1)
      top = y - total_h * 0.55
      cy = top
      table.children.each_with_index do |row, ri|
        cx = x
        row.children.each_with_index do |cell, ci|
          b = measure_list(cell.children)
          cell_w = widths[ci]? || b.width
          draw_list(io, cell.children, cx + (cell_w - b.width) / 2, cy + row_h[ri] / 2 + 0.1, scale)
          cx += cell_w + 0.3
        end
        cy += row_h[ri] + 0.2
      end
    end

    private def fmt(v : Float64) : String
      (v * 1000).round.to_i.to_s
    end
  end
end
