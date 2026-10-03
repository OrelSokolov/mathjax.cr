# SVG output in the MathJax v3 structure: a port of the v3 layout
# engine (output/common/Wrappers/*) — BBox(w,h,d,L,R,ic,sk), TeX
# inter-atom spacing (TEXSPACE matrix + BIN demotion, setTeXclass
# semantics), script / under-over / fraction / radical geometry and
# stretchy-delimiter piecewise assembly — emitting glyph outlines from
# Fonts::TexPaths as a single <defs> + <use xlink:href>, sized in ex
# and colored via currentColor.  Rasterizes via nanosvg.cr (see
# SVG_V3_PLAN.md).
require "../mml/node"
require "../fonts/tex_paths"
require "../fonts/tex_opclass"
require "../fonts/tex_smp"

module MathJax::Svg
  class PathsRenderer
    # MathML scriptsizemultiplier default: sqrt(1/2)
    SCRIPT_SCALE = Math.sqrt(0.5)

    # FontData.js defaultParams (the TeX fonts don't override these)
    X_HEIGHT        = 0.442
    NUM1            = 0.676
    NUM2            = 0.394
    NUM3            = 0.444
    DENOM1          = 0.686
    DENOM2          = 0.345
    SUP1            = 0.413
    SUP2            = 0.363
    SUP3            = 0.289
    SUB1            = 0.15
    SUB2            = 0.247
    SUP_DROP        = 0.386
    SUB_DROP        = 0.05
    AXIS            = 0.25
    RULE            = 0.06
    BOS1            = 0.111
    BOS2            = 0.167
    BOS3            = 0.2
    BOS4            = 0.6
    BOS5            = 0.1
    SCRIPTSPACE     = 0.05
    NULLELIM        = 0.12
    DELIM_FACTOR    = 901
    DELIM_SHORTFALL = 0.3
    SEPARATION      = 1.75
    EXTRA_IC        = 0.033
    SKEW_IC         = 0.75
    VFUZZ           = 0.1
    HFUZZ           = 0.1
    BIGDIMEN        = 1e6

    # TeX classes (MmlNode.js TEXCLASS)
    NONE_C = -1
    ORD    = 0
    OP     = 1
    BIN    = 2
    REL    = 3
    OPEN   = 4
    CLOSE  = 5
    PUNCT = 6
    INNER = 7
    VCENTER = 8

    # MmlNode.js TEXSPACE[prevClass][texClass]:
    # 0 = none, 1 = thin (3/18), 2 = medium (4/18), 3 = thick (5/18),
    # -1 = no space.
    TEXSPACE = {
      {0, -1, 2, 3, 0, 0, 0, 1},
      {-1, -1, 0, 3, 0, 0, 0, 1},
      {2, 2, 0, 0, 2, 0, 0, 2},
      {3, 3, 0, 0, 3, 0, 0, 3},
      {0, 0, 0, 0, 0, 0, 0, 0},
      {0, -1, 2, 3, 0, 0, 0, 1},
      {1, 1, 0, 1, 1, 1, 1, 1},
      {1, -1, 2, 3, 1, 0, 1, 1},
    }
    SPACES = {0.0, 3 / 18, 4 / 18, 5 / 18}

    # Chars the TeX mappings mark largeop+movablelimits (plus \int-like).
    LARGEOPS = {'∑', '∏', '∐', '∫', '∬', '∭', '∮', '∯', '∮', '∰',
                '⋀', '⋁', '⋂', '⋃', '⨀', '⨁', '⨂', '⨄', '⨆'}

    # Function names that carry movablelimits in the TeX mappings.
    LIMIT_FUNCS = {"lim", "max", "min", "sup", "inf", "det", "dim",
                   "liminf", "limsup", "proj", "arg", "gcd", "lcm",
                   "mod", "bmod", "Pr"}

    # mathvariant attr -> id-prefix (face names as in TexPaths)
    FACE_OF_VARIANT = {
      "normal" => "N", "bold" => "B", "italic" => "I", "bold-italic" => "BI",
      "double-struck" => "D", "fraktur" => "F", "bold-fraktur" => "BF",
      "script" => "C", "bold-script" => "BC",
      "sans-serif" => "SS", "bold-sans-serif" => "BSS",
      "sans-serif-italic" => "SSI", "sans-serif-bold-italic" => "SSBI",
      "monospace" => "M",
    }

    # ------------------------------------------------------------------
    # Layout boxes

    class BBox
      property w = 0.0
      property h = -BIGDIMEN
      property d = -BIGDIMEN
      property l = 0.0 # TeX spacing on the left (v3 bbox.L)
      property r = 0.0 # explicit rspace (TeX output never sets it)
      property ic = 0.0
      property sk = 0.0

      def append(o : BBox)
        @w += o.w + o.l + o.r
        @h = o.h if o.h > @h
        @d = o.d if o.d > @d
      end

      def combine(o : BBox, x = 0.0, y = 0.0)
        w = x + o.w + o.l + o.r
        h = y + o.h
        d = o.d - y
        @w = w if w > @w
        @h = h if h > @h
        @d = d if d > @d
      end

      def clean
        @w = 0.0 if @w <= -BIGDIMEN
        @h = 0.0 if @h <= -BIGDIMEN
        @d = 0.0 if @d <= -BIGDIMEN
        @w = 0.0 if @w < 0 && @w > -1.0
      end
    end

    record Ctx, display : Bool, level : Int32, prime : Bool = false do
      def scale : Float64
        SCRIPT_SCALE ** level.clamp(0, 2).to_f
      end
    end

    # ------------------------------------------------------------------
    # Renderer state

    @doc_id = 1
    @defs = {} of String => String
    @defs_key = {} of String => String
    @uses = [] of String
    @boxes = {} of Mml::Node => BBox
    @lspace = {} of Mml::Node => Float64
    @prev_autoop = false
    # stretched-variant decisions per mo: node -> {dir, wh}
    @mo_stretch = {} of Mml::Node => {Int32, Array(Float64)}
    # resolved mo layout (variant/stretches) per node, set by mo_bbox
    @mo_info = {} of Mml::Node => MoInfo

    # Everything draw_mo needs, resolved once by mo_bbox.
    record MoInfo, cp : Int32, dir : Int32, face : String, size : Int32,
                     wh : Array(Float64)?, d_clamped : Float64,
                     center_off : Float64, accent_off : Float64,
                     glyph_w : Float64

    def initialize(@display : Bool = false)
    end

    def self.call(node : Mml::Node, display : Bool = false) : String
      new(display).render(node)
    end

    def render(node : Mml::Node) : String
      inner = node.children.first? || node
      ctx = Ctx.new(@display, 0)
      assign_spacing([inner], nil, ctx)
      box = bbox_of(inner, ctx)
      draw_node(inner, 0.0, 0.0, ctx)

      w = {box.w, 0.001}.max
      h = {box.h + box.d, 0.001}.max
      String.build do |io|
        io << %(<svg style="vertical-align: #{ex_str(-box.d)};" )
        io << %(xmlns="http://www.w3.org/2000/svg" )
        io << %(width="#{ex_str(w)}" height="#{ex_str(h)}" role="img" focusable="false" )
        io << %(viewBox="0 #{fmt(-box.h * 1000)} #{fmt(w * 1000)} #{fmt(h * 1000)}" )
        io << %(xmlns:xlink="http://www.w3.org/1999/xlink">)
        io << "<defs>"
        @defs.each do |id, d|
          io << %(<path id="#{id}" d="#{d}"></path>)
        end
        io << "</defs>"
        io << %(<g stroke="currentColor" fill="currentColor" stroke-width="0" transform="scale(1,-1)">)
        @uses.each { |u| io << u }
        io << "</g></svg>"
      end
    end

    # v3 OutputJax.fixed(m, n): toFixed(n) with trailing zeros stripped
    private def fixed_s(v : Float64, n : Int32) : String
      return "0" if v.abs < 0.0006
      sprintf("%.#{n}f", v).gsub(/\.?0+$/, "")
    end

    private def fmt(v : Float64) : String
      fixed_s(v, 1)
    end

    private def fmt3(v : Float64) : String
      fixed_s(v, 3)
    end

    # v3 SVG.ex(m): CSS length in ex units (x_height = 0.442em)
    private def ex_str(m : Float64) : String
      m = m / X_HEIGHT
      return "0" if m.abs < 0.001
      fixed_s(m, 3) + "ex"
    end

    private def length2em(s : String?, default : Float64 = 0.0) : Float64
      return default if s.nil? || s.empty?
      if m = s.match(/\A\s*([-\d.]+)\s*(em|ex|pt|px|mu)?\s*\z/)
        v = m[1].to_f
        case m[2]?
        when "ex"  then v / 2
        when "pt"  then v / 10
        when "px"  then v / 16
        when "mu"  then v / 18
        else            v
        end
      else
        default
      end
    end

    # ------------------------------------------------------------------
    # Glyph resolution

    private def glyph_of(face : String, cp : Int32) : BBox?
      m = Fonts::TexPaths::METRICS.dig?(face, cp) || Fonts::TexPaths::METRICS.dig?("N", cp)
      return nil unless m
      b = BBox.new
      b.w = m[2]
      b.h = m[0]
      b.d = m[1]
      b.ic = m[3]
      b.sk = m[4]
      b
    end

    private def path_of(face : String, cp : Int32) : String?
      Fonts::TexPaths::PATHS.dig?(face, cp) || Fonts::TexPaths::PATHS.dig?("N", cp)
    end

    # v3 FontData.defaultMoMap / defaultAccentMap — output-side remaps
    # applied by the mo wrapper for single-character mo text.
    MO_REMAP = {0x2D => 0x2212}
    ACCENT_REMAP = {
      0x300 => 0x2CB, 0x301 => 0x2CA, 0x302 => 0x2C6, 0x303 => 0x2DC,
      0x304 => 0x2C9, 0x306 => 0x2D8, 0x307 => 0x2D9, 0x308 => 0x00A8,
      0x30A => 0x2DA, 0x30C => 0x2C7, 0x2192 => 0x20D7,
      0x20D0 => 0x21BC, 0x20D1 => 0x21C0, 0x20D6 => 0x2190, 0x20E1 => 0x2194,
      0x20F0 => 0x002A, 0x20EC => 0x21C1, 0x20ED => 0x21BD,
      0x20EE => 0x2190, 0x20EF => 0x2192,
    }
    # v3 variantForm symbols (\prime family, \hbar): rendered in '-tex-variant'
    VARIANT_FORM_CPS = {0x2032, 0x2033, 0x2034, 0x2057, 0x210F}

    # face prefix + TexSmp variant name for a token node
    private def face_variant_of(node : Mml::Node) : {String, String}
      text = node.text.to_s
      if text.size == 1 && text[0].ord.in?(VARIANT_FORM_CPS)
        return {"V", "variant"}
      end
      variant = node["mathvariant"]?
      fv = variant ? FACE_OF_VARIANT[variant]? : nil
      return {fv.not_nil!, variant.not_nil!} if fv && variant
      case node.kind
      when "mi"
        node.text.to_s.size == 1 ? {"I", "italic"} : {"N", "normal"}
      else
        {"N", "normal"}
      end
    end

    private def remap_cp(variant : String, cp : Int32) : Int32
      # \mathcal resolves to v3's '-tex-calligraphic' (real C-face glyphs
      # at the plain codepoint); only the unicode 'script' fallback variant
      # carries SMP remaps.
      return cp if variant == "script"
      Fonts::TexSmp::SMP.dig?(variant, cp) || cp
    end

    # The size-variant face for delimiter index i (FontData.getSizeVariant)
    private def size_variant_face(cp : Int32, delim, i : Int32) : String
      v = delim.variants[i]? || Fonts::TexPaths::SIZE_VARIANTS[i]? || "N"
      v
    end

    # ------------------------------------------------------------------
    # Emission (y-up layout coords; translate in 1000-unit g-space)

    private def use_glyph(face : String, cp : Int32, x : Float64, y : Float64,
                          scale : Float64) : Nil
      d = path_of(face, cp)
      return if d.nil?
      key = "#{face}-#{cp.to_s(16).upcase}"
      gid = @defs_key[key]? || begin
        id = "MJX-#{@doc_id}-TEX-#{key}"
        @defs_key[key] = id
        @defs[id] = d.not_nil!
        id
      end
      tx = (x * 1000).round(3)
      ty = (y * 1000).round(3)
      @uses << if scale == 1.0
        %(<use data-c="#{cp.to_s(16)}" xlink:href="##{gid}" transform="translate(#{fmt(tx)},#{fmt(ty)})"></use>)
      else
        %(<use data-c="#{cp.to_s(16)}" xlink:href="##{gid}" transform="translate(#{fmt(tx)},#{fmt(ty)}) scale(#{fmt3(scale)})"></use>)
      end
    end

    private def use_svg_piece(face : String, cp : Int32, gx : Float64, gy : Float64,
                              wu : Float64, hu : Float64, view : String,
                              inner_scale : String?) : Nil
      d = path_of(face, cp)
      return unless d
      key = "#{face}-#{cp.to_s(16).upcase}"
      gid = @defs_key[key]? || begin
        id = "MJX-#{@doc_id}-TEX-#{key}"
        @defs_key[key] = id
        @defs[id] = d.not_nil!
        id
      end
      frag = if (iscale = inner_scale)
        %(<use data-c="#{cp.to_s(16)}" xlink:href="##{gid}" transform="scale(#{iscale})"></use>)
      else
        %(<use data-c="#{cp.to_s(16)}" xlink:href="##{gid}"></use>)
      end
      @uses << %(<svg width="#{fmt3(wu * 1000)}" height="#{fmt3(hu * 1000)}" x="#{fmt3(gx * 1000)}" )
      @uses << %(y="#{fmt3(gy * 1000)}" viewBox="#{view}">#{frag}</svg>)
    end

    private def rect(x : Float64, y : Float64, w : Float64, h : Float64) : Nil
      @uses << %(<rect width="#{fmt3(w * 1000)}" height="#{fmt3(h * 1000)}" )
      @uses << %(x="#{fmt3(x * 1000)}" y="#{fmt3(y * 1000)}"></rect>)
    end

    # ------------------------------------------------------------------
    # TeX class + spacing (MmlNode.js setTeXclass semantics)

    private def tex_class(node : Mml::Node) : Int32
      case node.kind
      when "mi"
        text = node.text.to_s
        text.size > 1 && text.matches?(/\A[a-zA-Z][a-zA-Z0-9]*\z/) ? OP : ORD
      when "mn", "mtext", "ms", "mspace" then ORD
      when "mo"
        if side = node["side"]?
          side == "open" ? OPEN : CLOSE
        elsif c = Fonts::TexOpClass::INFIX[node.text.to_s]?
          c
        elsif node.text.to_s.size > 1
          OP
        elsif largeop?(node)
          OP
        else
          ORD
        end
      when "mfrac", "mtable" then INNER
      when "msub", "msup", "msubsup", "munder", "mover", "munderover"
        base = node.children.first?
        base ? tex_class(base) : ORD
      else
        ORD
      end
    end

    private def largeop?(node : Mml::Node) : Bool
      text = node.text.to_s
      text.size == 1 && LARGEOPS.includes?(text[0])
    end

    private def movable_limits?(node : Mml::Node) : Bool
      mo = core_mo(node)
      return false unless mo
      text = mo.text.to_s
      return true if largeop?(mo)
      text.size > 1 && LIMIT_FUNCS.includes?(text)
    end

    # Unwrap scripts/groups to the core mo (v3 coreMO)
    private def core_mo(node : Mml::Node) : Mml::Node?
      case node.kind
      when "mo" then node
      when "msub", "msup", "msubsup", "munder", "mover", "munderover"
        base = node.children.first?
        base ? core_mo(base) : nil
      when "mrow", "mstyle", "mpadded", "mphantom"
        node.children.size == 1 ? core_mo(node.children.first) : nil
      else nil
      end
    end

    private def embellished?(node : Mml::Node?) : Bool
      return false unless node
      case node.kind
      when "mo" then true
      when "msub", "msup", "msubsup", "munder", "mover", "munderover"
        embellished?(node.children.first?)
      else false
      end
    end

    # assign_spacing: walk siblings computing each node's left spacing.
    # Returns the effective tex class of the last node (v3 setTeXclass).
    private def assign_spacing(nodes : Array(Mml::Node), prev : Int32?,
                                ctx : Ctx) : Int32?
      last = prev
      nodes.each_with_index do |n, i|
        autoop = @prev_autoop
        last = walk_class(n, last, ctx, i == nodes.size - 1, autoop)
      end
      last
    end

    private def walk_class(node : Mml::Node, prev : Int32?, ctx : Ctx,
                           is_last : Bool, prev_autoop = false) : Int32?
      @prev_autoop = false
      cls = tex_class(node)
      case node.kind
      when "mrow", "math", "merror"
        fenced = node.children.any? { |c| c.kind == "mo" && c["side"]? }
        last = assign_spacing(node.children, fenced ? nil : prev, ctx)
        @prev_autoop = false
        fenced ? INNER : last
      when "mfrac", "mtable"
        @lspace[node] = space_between(prev, INNER, ctx)
        assign_spacing(node.children, nil, ctx)
        INNER
      when "mtr", "mlabeledtr"
        # transparent row: the TeX chain continues through the cells
        assign_spacing(node.children, prev, ctx)
        ORD
      when "mtd"
        # v3 mtd is an mrow subclass — transparent for the chain
        assign_spacing(node.children, prev, ctx)
      when "msqrt", "mroot", "menclose", "mpadded"
        @lspace[node] = space_between(prev, ORD, ctx)
        assign_spacing(node.children, nil, ctx)
        ORD
      when "mstyle", "mphantom"
        # v3 default setTeXclass: mstyle passes the sibling chain through
        # (texClass null -> returns prev); the TeX parser links the tokens
        # pushed inside it as a fresh chain.
        assign_spacing(node.children, nil, ctx) if node.kind == "mstyle"
        @prev_autoop = false
        prev
      when "msub", "msup", "msubsup", "munder", "mover", "munderover"
        base = node.children.first?
        if base && (base.kind == "mi" || embellished?(base))
          # base continues the chain; its L moves to this container
          bcls = base.kind == "mo" ? adjust_class(base, tex_class(base), prev, false, prev_autoop) : tex_class(base)
          @lspace[node] = space_between(prev, bcls, ctx)
          cls = bcls
        else
          @lspace[node] = space_between(prev, ORD, ctx)
          cls = ORD
        end
        # v3: script children inherit scriptlevel + 1, which suppresses
        # positive TeX spacing inside them (MmlNode.texSpacing)
        node.children.each_with_index do |c, i|
          walk_class(c, nil, i == 0 ? ctx : Ctx.new(false, ctx.level + 1, true), true)
        end
        cls
      else
        cls = adjust_class(node, cls, prev, is_last, prev_autoop) if node.kind == "mo"
        @lspace[node] = space_between(prev, cls, ctx)
        @prev_autoop = node.kind == "mi" && node.text.to_s.size > 1
        cls
      end
    end

    # mo.js adjustTeXclass: BIN demotion at row edges / after BIN-likes;
    # autoOP demotion of the previous node.
    private def adjust_class(node : Mml::Node, cls : Int32, prev : Int32?,
                             is_last : Bool, prev_autoop : Bool) : Int32
      pc = prev || NONE_C
      pc = ORD if prev_autoop && (cls == BIN || cls == REL)
      if cls == BIN && pc.in?({NONE_C, BIN, OP, REL, OPEN, PUNCT})
        ORD
      elsif cls == BIN && is_last
        ORD
      else
        cls
      end
    end

    private def space_between(prev : Int32?, cls : Int32, ctx : Ctx) : Float64
      pc = prev.nil? || prev == NONE_C ? NONE_C : prev
      return 0.0 if pc == NONE_C || cls == NONE_C
      pc = ORD if pc == VCENTER
      c = cls == VCENTER ? ORD : cls
      v = TEXSPACE[pc]? && TEXSPACE[pc][c]? || 0
      return 0.0 if v < 0
      return 0.0 if ctx.level > 0
      SPACES[v]
    end

    # ------------------------------------------------------------------
    # BBox computation (memoized per node)

    private def bbox_of(node : Mml::Node, ctx : Ctx) : BBox
      if b = @boxes[node]?
        return b
      end
      box = compute_bbox(node, ctx)
      box.l = @lspace[node]? || 0.0
      @boxes[node] = box
      box
    end

    private def compute_bbox(node : Mml::Node, ctx : Ctx) : BBox
      case node.kind
      when "mi", "mn", "mtext", "ms" then token_bbox(node, ctx)
      when "mo"                       then mo_bbox(node, ctx, nil, false)
      when "mspace"
        b = BBox.new
        b.w = length2em(node["width"]?, 0.0) * ctx.scale
        b
      when "mrow", "math", "merror"   then row_bbox(node, ctx)
      when "mstyle"                   then style_bbox(node, ctx)
      when "mphantom"                 then list_bbox(node.children, ctx)
      when "mpadded"
        b = list_bbox(node.children, ctx)
        if w = node["width"]?
          b.w = length2em(w, b.w)
        end
        b
      when "mfrac"                    then frac_bbox(node, ctx)
      when "msub", "msup", "msubsup",
           "munder", "mover", "munderover" then script_bbox(node, ctx)
      when "msqrt", "mroot"           then sqrt_bbox(node, ctx)
      when "mtable"                   then table_bbox(node, ctx)
      when "menclose"                 then enclose_bbox(node, ctx)
      else
        list_bbox(node.children, ctx)
      end
    end

    private def list_bbox(nodes : Array(Mml::Node), ctx : Ctx) : BBox
      box = BBox.new
      nodes.each { |c| box.append(bbox_of(c, ctx)) }
      box.clean
      box
    end

    # v3 mrow: stretch stretchy children to the common H/D of siblings.
    private def row_bbox(node : Mml::Node, ctx : Ctx) : BBox
      children = node.children
      stretch_children_v(children, ctx)
      list_bbox(children, ctx)
    end

    private def stretch_children_v(children : Array(Mml::Node), ctx : Ctx) : Nil
      return if children.size <= 1
      stretchy = children.select { |c| can_stretch?(c, 1) }
      return if stretchy.empty?
      all = stretchy.size == children.size
      h = 0.0
      d = 0.0
      children.each do |c|
        next unless all || !can_stretch?(c, 1)
        b = bbox_of(c, ctx)
        h = b.h if b.h > h
        d = b.d if b.d > d
      end
      stretchy.each do |c|
        @mo_stretch[c] = {1, [h, d]}
        @boxes.delete(c)
      end
    end

    # ------------------------------------------------------------------
    # Tokens

    private def token_bbox(node : Mml::Node, ctx : Ctx) : BBox
      box = BBox.new
      face, variant = face_variant_of(node)
      first_sk = 0.0
      last_ic = 0.0
      node.text.to_s.each_char_with_index do |ch, i|
        cp = remap_cp(variant, ch.ord)
        g = glyph_of(face, cp)
        next unless g
        box.w += g.w
        box.h = g.h if g.h > box.h
        box.d = g.d if g.d > box.d
        first_sk = g.sk if i == 0
        last_ic = g.ic
      end
      s = ctx.scale
      box.w *= s
      box.h *= s
      box.d *= s
      box.ic = last_ic * s
      box.sk = first_sk * s
      box
    end

    # ------------------------------------------------------------------
    # mo: variant selection, stretching, symmetric centering

    private def can_stretch_dir(node : Mml::Node) : Int32
      return 0 unless node.kind == "mo"
      return 0 unless node["stretchy"]? == "true"
      text = node.text.to_s
      return 0 unless text.size == 1
      delim = Fonts::TexPaths::DELIMITERS[text[0].ord]?
      return 0 unless delim
      delim.dir == "V" ? 1 : 2
    end

    private def can_stretch?(node : Mml::Node, dir : Int32) : Bool
      can_stretch_dir(node) == dir
    end

    private def symmetric?(node : Mml::Node) : Bool
      return false unless node.kind == "mo"
      return true if node["side"]?
      return true if node["minsize"]?
      largeop?(node)
    end

    private def mo_face(node : Mml::Node, ctx : Ctx) : String
      text = node.text.to_s
      if text.size == 1 && text[0].ord.in?(VARIANT_FORM_CPS)
        return "V"
      end
      if text.size == 1 && LARGEOPS.includes?(text[0])
        want = ctx.display ? "LO" : "SO"
        return want if Fonts::TexPaths::PATHS.dig?(want, text[0].ord)
        alt = ctx.display ? "SO" : "LO"
        return alt if Fonts::TexPaths::PATHS.dig?(alt, text[0].ord)
      end
      "N"
    end

    # wh: stretch target (nil = unstretched); exact: msqrt/bevel semantics
    private def mo_bbox(node : Mml::Node, ctx : Ctx, wh : Array(Float64)?,
                        exact : Bool) : BBox
      box = BBox.new
      text = node.text.to_s
      cp = text.empty? ? 0 : text[0].ord
      # v3 mo wrapper remapChars: single-char mo text goes through the
      # accent map (accent mo) or the plain mo map
      if text.size == 1
        cp = (node["accent"]? == "true" ? ACCENT_REMAP[cp]? : MO_REMAP[cp]?) || cp
      end
      scale = ctx.scale
      sdir = can_stretch_dir(node)
      stretch = @mo_stretch[node]?
      wh = stretch ? stretch[1] : (wh.nil? && sdir != 0 ? [0.0, 0.0] : wh)
      wh = wh.map(&.itself) if wh # defensive copy

      face = mo_face(node, ctx)
      size = 0
      symmetric = symmetric?(node) && sdir != 2
      center_off = 0.0
      accent_off = 0.0
      glyph_w = 0.0
      d_clamped = 0.0
      delim = Fonts::TexPaths::DELIMITERS[cp]?

      if wh
        # getWH
        if wh.size == 1
          d_target = wh[0]
        else
          h0, d0 = wh
          d_target = symmetric ? 2 * {h0 - AXIS * scale, d0 + AXIS * scale}.max : h0 + d0
        end
        min = length2em(node["minsize"]?, 0.0)
        max = length2em(node["maxsize"]?, BIGDIMEN)
        d_clamped = {min, {max, d_target}.min}.max
        mathaccent = node["accent"]? == "true"
        df = DELIM_FACTOR / 1000.0
        m = if min > 0 || exact
          d_clamped
        elsif mathaccent
          {d_clamped / df, d_clamped + DELIM_SHORTFALL}.min
        else
          {d_clamped * df, d_clamped - DELIM_SHORTFALL}.max
        end
        size = -2
        if delim && !delim.sizes.empty?
          delim.sizes.each_with_index do |sz, i|
            next unless sz >= m
            i -= 1 if mathaccent && i > 0
            size = i
            face = size_variant_face(delim, i)
            break
          end
        end
        if size == -2
          if delim && !delim.stretch.empty?
            size = -1
            d_clamped = check_extended_height(d_clamped, delim)
            if wh.size == 1 # horizontal
              box.w = d_clamped
              if hdw = delim.hdw
                box.h = hdw[0] * scale
                box.d = hdw[1] * scale
              end
            else
              h, d = get_baseline(wh, d_clamped, delim, symmetric, scale)
              box.h = h
              box.d = d
              box.w = (delim.hdw ? delim.hdw[2] : 0.5) * scale
            end
          else
            i = (delim && !delim.sizes.empty?) ? delim.sizes.size - 1 : 0
            size = i
            face = delim ? size_variant_face(delim, i) : "N"
          end
        end
      end

      if size >= 0
        if g = glyph_of(face, cp)
          glyph_w = g.w * scale
          box.w = glyph_w
          box.h = g.h * scale
          box.d = g.d * scale
          box.ic = g.ic * scale
          box.sk = g.sk * scale
          if symmetric && sdir != 2
            center_off = (box.h + box.d) / 2 + AXIS * scale - box.h
            box.h += center_off
            box.d -= center_off
          end
          if node["accent"]? == "true" && sdir == 0
            accent_off = -glyph_w / 2
            box.w = 0.0
          elsif box.ic > 0
            # v3 mo copySkewIC: the advance includes the italic correction
            box.w += box.ic
          end
        end
      end
      # mathaccent over a stretched/accent glyph: zero width
      if node["accent"]? == "true" && size >= 0 && sdir != 0
        box.w = 0.0
      end

      @mo_info[node] = MoInfo.new(cp, sdir, face, size, wh, d_clamped,
                                  center_off, accent_off, glyph_w)
      box.clean
      box
    end

    # v3 mo.js checkExtendedHeight: round the stretch target up to whole
    # extension pieces when the delimiter declares fullExt.
    private def check_extended_height(d : Float64, delim) : Float64
      fe = delim.fullext
      return d if fe.empty?
      ext_size, end_size = fe
      n = (({0.0, d - end_size}.max) / ext_size).ceil
      end_size + n * ext_size
    end

    # v3 mo.js getBaseline
    private def get_baseline(wh : Array(Float64), hd : Float64, delim,
                             symmetric : Bool, scale : Float64) : {Float64, Float64}
      has_whd = wh.size == 2 && (wh[0] + wh[1] == hd)
      h0, d0 = has_whd ? {wh[0], wh[1]} : {hd, 0.0}
      h = h0 + d0
      d = 0.0
      if symmetric
        a = AXIS * scale
        h = 2 * {h0 - a, d0 + a}.max if has_whd
        d = h / 2 - a
      elsif has_whd
        d = d0
      else
        ch, cd = delim.hdw ? {delim.hdw[0], delim.hdw[1]} : {0.75, 0.25}
        d = cd * (h / (ch + cd))
      end
      {h - d, d}
    end

    private def size_variant_face(delim, i : Int32) : String
      v = delim.variants[i]?
      v ? Fonts::TexPaths::SIZE_VARIANTS[v]? || "N" : Fonts::TexPaths::SIZE_VARIANTS[i]? || "N"
    end

    private def stretch_variant_face(delim, i : Int32) : String
      v = delim.stretchv[i]?
      v ? Fonts::TexPaths::SIZE_VARIANTS[v]? || "N" : "N"
    end

    # ------------------------------------------------------------------
    # mfrac

    record FracGeom, w : Float64, t : Float64, num_x : Float64, den_x : Float64,
                      num_y : Float64, den_y : Float64, rect_w : Float64,
                      nbox : BBox, dbox : BBox, nctx : Ctx, dctx : Ctx,
                      atop : Bool

    private def frac_children_ctx(ctx : Ctx, prime : Bool) : Ctx
      level = (!ctx.display || ctx.level > 0) ? ctx.level + 1 : ctx.level
      Ctx.new(false, level, prime)
    end

    private def frac_geom(node : Mml::Node, ctx : Ctx) : FracGeom
      num, den = node.children
      # v3 mfrac: num keeps the incoming prime flag, den gets prime=true
      nctx = frac_children_ctx(ctx, ctx.prime)
      dctx = frac_children_ctx(ctx, true)
      nbox = bbox_of(num, nctx)
      dbox = bbox_of(den, dctx)
      t = length2em(node["linethickness"]?, RULE)
      display = ctx.display && ctx.level == 0
      pad = NULLELIM * nctx.scale
      nw = nbox.l + nbox.w + nbox.r
      dw = dbox.l + dbox.w + dbox.r
      w = {nw, dw}.max
      if t > 0
        t_cap = (display ? 3.5 : 1.5) * t
        u = (display ? NUM1 : NUM2) - AXIS - t_cap
        v = (display ? DENOM1 : DENOM2) + AXIS - t_cap
        num_y = AXIS * nctx.scale + t_cap + {nbox.d, u}.max
        den_y = AXIS * nctx.scale - t_cap - {dbox.h, v}.max
        FracGeom.new(w + 2 * pad + 0.2, t, pad + 0.1 + (w - nw) / 2 + nbox.l,
                     pad + 0.1 + (w - dw) / 2 + dbox.l, num_y, den_y, w + 0.2,
                     nbox, dbox, nctx, dctx, false)
      else
        # atop (binom): mfrac.js getUVQ
        u0 = display ? NUM1 : NUM3
        v0 = display ? DENOM1 : DENOM2
        p = (display ? 7 : 3) * RULE
        q = (u0 - nbox.d) - (dbox.h - v0)
        if q < p
          u0 += (p - q) / 2
          v0 += (p - q) / 2
        end
        FracGeom.new(w + 2 * pad, 0.0, pad + (w - nw) / 2 + nbox.l,
                     pad + (w - dw) / 2 + dbox.l, u0, -v0, 0.0,
                     nbox, dbox, nctx, dctx, true)
      end
    end

    private def frac_bbox(node : Mml::Node, ctx : Ctx) : BBox
      g = frac_geom(node, ctx)
      box = BBox.new
      box.combine(g.nbox, 0, g.num_y)
      box.combine(g.dbox, 0, g.den_y)
      box.w = g.w
      box
    end

    # ------------------------------------------------------------------
    # scripts (msub/msup/msubsup + underover with movablelimits)

    # Unwrap single-child wrappers to the script base core (scriptbase.js)
    private def base_core(node : Mml::Node) : Mml::Node?
      cur = node
      while cur && cur.kind.in?({"mrow", "mstyle", "mpadded", "mphantom"}) &&
            cur.children.size == 1
        cur = cur.children.first
      end
      cur
    end

    private def prime_script?(node : Mml::Node?) : Bool
      return false unless node
      text = node.text.to_s
      node.kind == "mo" && {"′", "″", "‴", "⁗"}.includes?(text)
    end

    record ScriptGeom, base_x : Float64, sub_x : Float64, sub_y : Float64,
                         sup_x : Float64, sup_y : Float64, w : Float64,
                         bbox : BBox

    private def script_geom(node : Mml::Node, ctx : Ctx) : ScriptGeom
      children = node.children
      base = children[0]
      case node.kind
      when "msubsup", "munderover"
        sub = children[1]?
        sup = children[2]?
      when "msub", "munder"
        sub = children[1]?
        sup = nil
      else # msup, mover
        sub = nil
        sup = children[1]?
      end
      kind = node.kind
      # movablelimits inline: munder* -> script-style (v3 hasMovableLimits)
      if kind.in?({"munder", "mover", "munderover"}) && !ctx.display &&
         movable_limits?(node)
        if kind == "munderover"
          sub, sup = children[1], children[2]
        elsif kind == "munder"
          sub, sup = children[1], nil
        else
          sub, sup = nil, children[1]
        end
        kind = "msubsup"
      end

      subctx = Ctx.new(false, ctx.level + 1, true)
      supctx = Ctx.new(false, ctx.level + 1, ctx.prime)
      base_box = bbox_of(base, ctx)
      core = base_core(base)
      core_box = core ? bbox_of(core, ctx) : base_box
      base_is_char = core && core.kind.in?({"mo", "mi", "mn"}) &&
                     core.text.to_s.size == 1 &&
                     !(core.kind == "mo" && @mo_stretch.has_key?(core))
      largeop = core ? largeop?(core) : false
      base_ic = core_box.ic

      sbox = sub ? bbox_of(sub, subctx) : nil
      pbox = sup ? bbox_of(sup, supctx) : nil

      base_char_zero = ->(n : Float64) { base_is_char && !largeop ? 0.0 : n }
      line_above = kind == "munderover" && prime_line?(children[2]?)
      line_below = kind != "msup" && prime_line?(children[1]?)
      is_math_accent = base_is_char && (sup && core_mo(sup) && core_mo(sup).not_nil!["accent"]? == "true" || sub && core_mo(sub) && core_mo(sub).not_nil!["accent"]? == "true")

      use_ic = kind == "msup"
      base_remove_ic = !line_above && !line_below && (!use_ic || is_math_accent)
      base_width = base_box.w - (base_remove_ic ? base_ic : 0) + EXTRA_IC
      adjusted_ic = base_ic > 0 ? 1.05 * base_ic + 0.05 : 0.0

      get_v = ->do
        return 0.0 unless sbox
        shift = length2em(node["subscriptshift"]?, SUB1)
        {base_char_zero.call(base_box.d + SUB_DROP), shift,
         sbox.not_nil!.h - 4 / 5 * X_HEIGHT}.max
      end
      get_u = ->do
        return 0.0 unless pbox
        prime = ctx.prime || prime_script?(sup)
        p = prime ? SUP3 : (ctx.display ? SUP1 : SUP2)
        shift = length2em(node["superscriptshift"]?, p)
        {base_char_zero.call(base_box.h - SUP_DROP), shift,
         pbox.not_nil!.d + X_HEIGHT / 4}.max
      end

      box = BBox.new
      box.append(base_box)
      case kind
      when "msub"
        v = get_v.call
        box.combine(sbox.not_nil!, base_width, -v)
        box.w += SCRIPTSPACE
        ScriptGeom.new(0.0, base_width, -v, 0.0, 0.0, box.w, box)
      when "msup"
        u = get_u.call
        x_off = adjusted_ic - (base_remove_ic ? 0.0 : base_ic)
        box.combine(pbox.not_nil!, base_width + x_off, u)
        box.w += SCRIPTSPACE
        ScriptGeom.new(0.0, 0.0, 0.0, base_width + x_off, u, box.w, box)
      else # msubsup
        u = get_u.call
        v0 = {base_char_zero.call(base_box.d + SUB_DROP), SUB2}.max
        if sbox && pbox
          t = 3 * RULE
          q = (u - pbox.not_nil!.d) - (sbox.not_nil!.h - v0)
          if q < t
            v0 += t - q
            p = 4 / 5 * X_HEIGHT - (u - pbox.not_nil!.d)
            if p > 0
              u += p
              v0 -= p
            end
          end
        end
        box.combine(sbox.not_nil!, base_width, -v0) if sbox
        box.combine(pbox.not_nil!, base_width + adjusted_ic, u) if pbox
        box.w += SCRIPTSPACE
        ScriptGeom.new(0.0, base_width, -v0, base_width + adjusted_ic, u, box.w, box)
      end
    end

    private def prime_line?(node : Mml::Node?) : Bool
      return false unless node
      core_mo(node).try &.text.to_s == "―"
    end

    # ------------------------------------------------------------------
    # munder / mover / munderover

    record UnderOverGeom, base_x : Float64, under_x : Float64, under_y : Float64,
                           over_x : Float64, over_y : Float64, bbox : BBox

    private def accent_of(node : Mml::Node?, attr : String) : Bool
      return false unless node
      mo = core_mo(node)
      !!mo && mo["accent"]? == "true"
    end

    # v3 scriptbase.getDelta: (accent && !noskew ? sk : 0) + skewIcFactor*ic
    private def delta_of(base : Mml::Node, ctx : Ctx, noskew : Bool, accent : Bool) : Float64
      core = base_core(base)
      return 0.0 unless core
      b = bbox_of(core, ctx)
      (accent && !noskew ? b.sk : 0.0) + SKEW_IC * b.ic
    end

    private def underover_geom(node : Mml::Node, ctx : Ctx) : UnderOverGeom
      children = node.children
      base = children[0]
      under = node.kind == "mover" ? nil : children[1]?
      over = node.kind == "munder" ? nil : (node.kind == "mover" ? children[1]? : children[2]?)
      display = ctx.display

      base_ctx = ctx
      # scriptlevel: +1 unless accent (munderover.js getScriptlevel);
      # prime: under script always true, over keeps the incoming flag
      accent_over = accent_of(over, "accent")
      accent_under = accent_of(under, "accentunder")
      over_ctx = Ctx.new(false, accent_over ? ctx.level : ctx.level + 1, ctx.prime)
      under_ctx = Ctx.new(false, accent_under ? ctx.level : ctx.level + 1, true)

      # stretchChildren (horizontal): over/under stretchy mo -> base width
      if under && can_stretch?(under, 2)
        @mo_stretch[under] = {2, [bbox_of(base, base_ctx).w]}
        @boxes.delete(under)
      end
      if over && can_stretch?(over, 2)
        @mo_stretch[over] = {2, [bbox_of(base, base_ctx).w]}
        @boxes.delete(over)
      end

      base_box = bbox_of(base, base_ctx)
      under_box = under ? bbox_of(under, under_ctx) : nil
      over_box = over ? bbox_of(over, over_ctx) : nil

      accent = accent_over || accent_under

      # getOverKU
      u = 0.0
      if over_box
        ob = over_box.not_nil!
        t_sep = RULE * SEPARATION
        line_above = over && core_mo(over).try &.text.to_s == "―"
        tt = line_above ? 3 * RULE : t_sep
        d = ob.d
        k = accent_over ? tt : {BOS1, BOS3 - {0.0, d}.max}.max
        u = base_box.h + k + d
      end
      # getUnderKV
      v = 0.0
      if under_box
        ub = under_box.not_nil!
        t_sep = RULE * SEPARATION
        line_below = under && core_mo(under).try &.text.to_s == "―"
        tt = line_below ? 3 * RULE : t_sep
        h = ub.h
        k = accent_under ? tt : {BOS2, BOS4 - h}.max
        v = -(base_box.d + k + h)
      end

      # getDeltaW (align center)
      widths = [base_box.w]
      boxes = [base_box]
      deltas = [0.0]
      if under_box
        boxes << under_box.not_nil!
        widths << under_box.not_nil!.w
        deltas << (line_below2(under) ? 0.0 : -delta_of(base, ctx, true, false))
      end
      if over_box
        boxes << over_box.not_nil!
        widths << over_box.not_nil!.w
        deltas << (line_above2(over) ? 0.0 : delta_of(base, ctx, false, accent_over))
      end
      wmax = widths.max
      dw = widths.map_with_index { |wd, i| (wmax - wd) / 2 + deltas[i] }
      m = dw.min
      dw = dw.map { |x| x - m } if m < 0

      box = BBox.new
      box.combine(base_box, dw[0], 0.0)
      uw = under_box ? dw[1] : 0.0
      ow = over_box ? dw[under_box ? 2 : 1] : 0.0
      if under_box
        box.combine(under_box.not_nil!, uw, v)
      end
      if over_box
        box.combine(over_box.not_nil!, ow, u)
      end
      box.h += BOS5 if over_box
      box.d += BOS5 if under_box
      box.clean
      UnderOverGeom.new(dw[0], uw, v, ow, u, box)
    end

    private def line_below2(node : Mml::Node?) : Bool
      return false unless node
      core_mo(node).try &.text.to_s == "―"
    end

    private def line_above2(node : Mml::Node?) : Bool
      line_below2(node)
    end

    private def script_bbox(node : Mml::Node, ctx : Ctx) : BBox
      if node.kind.in?({"munder", "mover", "munderover"}) &&
         !(!ctx.display && movable_limits?(node))
        underover_geom(node, ctx).bbox
      else
        script_geom(node, ctx).bbox
      end
    end

    # ------------------------------------------------------------------
    # msqrt / mroot

    record SqrtGeom, surd_face : String, surd_cp : Int32, surd_size : Int32,
                     x : Float64, surd_y : Float64, rule_w : Float64,
                     rule_x : Float64, rule_y : Float64, bbox : BBox,
                     base : Mml::Node, base_x : Float64, base_ctx : Ctx,
                     root : Mml::Node?, root_x : Float64, root_y : Float64,
                     root_ctx : Ctx, stretch : Bool, d_clamped : Float64

    private def sqrt_geom(node : Mml::Node, ctx : Ctx) : SqrtGeom
      is_root = node.kind == "mroot"
      base = node.children[0]
      root = is_root ? node.children[1]? : nil
      # v3 msqrt/mroot: the base content inherits prime=true; the root
      # index keeps the incoming flag
      base_ctx = Ctx.new(ctx.display, ctx.level, true)
      base_box = bbox_of(base, base_ctx)
      root_ctx = Ctx.new(false, ctx.level + 2, ctx.prime)
      t = RULE * ctx.scale
      p = (ctx.display ? X_HEIGHT : RULE) * ctx.scale
      surd_h = base_box.h + base_box.d + 2 * t + p / 4
      # surd: stretched variant on 0x221A, exact
      surd_face, surd_size, d_clamped = surd_variant(surd_h - base_box.d, base_box.d, ctx.scale)

      # sbox (the surd mo box: width includes the italic correction,
      # v3 copySkewIC on mo)
      if surd_size >= 0
        g = glyph_of(surd_face, 0x221A).not_nil!
        sh = g.h * ctx.scale
        sd = g.d * ctx.scale
        sw = (g.w + g.ic) * ctx.scale
      else
        delim = Fonts::TexPaths::DELIMITERS[0x221A].not_nil!
        h, d = get_baseline([surd_h - base_box.d, base_box.d], d_clamped, delim, false, ctx.scale)
        sh = h
        sd = d
        sw = ((delim.hdw ? delim.hdw[2] : 0.5) + 0.02) * ctx.scale
      end
      sbox_h_total = sh + sd
      q = sbox_h_total > surd_h ? (sbox_h_total - (surd_h - 2 * t - p / 2)) / 2 : t + p / 4
      height = base_box.h + q + t

      dx = 0.0
      root_x = 0.0
      root_y = 0.0
      if root
        rbox = bbox_of(root, root_ctx)
        offset = (surd_size < 0 ? 0.5 : 0.6) * sw
        w_r = rbox.w
        wr = {w_r, offset}.max
        dx = wr - w_r
        b = (surd_size < 0 ? 1.9 : 0.55 * (sh + sd)) - ((sh + sd) - height)
        root_y = b + {0.0, rbox.d}.max
        root_x = dx
        surd_x = wr - offset
      else
        surd_x = 0.0
      end

      box = BBox.new
      box.h = height + t
      if root
        rbox = bbox_of(root, root_ctx)
        box.combine(rbox, 0.0, root_y)
      end
      surd_box = BBox.new
      surd_box.h = sh
      surd_box.d = sd
      surd_box.w = sw
      box.combine(surd_box, surd_x, height - sh)
      box.combine(base_box, surd_x + sw, 0.0)
      box.clean

      SqrtGeom.new(surd_face, 0x221A, surd_size, surd_x, height - sh,
                   base_box.w, surd_x + sw, height - t, box, base,
                   surd_x + sw, base_ctx, root, root_x, root_y, root_ctx,
                   surd_size < 0, d_clamped)
    end

    # v3 getStretchedVariant for the radical sign (exact)
    private def surd_variant(h : Float64, d : Float64, scale : Float64)
      delim = Fonts::TexPaths::DELIMITERS[0x221A]?.not_nil!
      d_target = h + d
      m = d_target
      face = "N"
      size = 0
      delim.sizes.each_with_index do |sz, i|
        next unless sz >= m
        size = i
        face = size_variant_face(delim, i)
        break
      end
      if size == 0 && (delim.sizes.empty? || delim.sizes[0] < m)
        if !delim.stretch.empty?
          size = -1
        else
          size = delim.sizes.empty? ? 0 : delim.sizes.size - 1
          face = size_variant_face(delim, size)
        end
      end
      {face, size, d_target}
    end

    private def sqrt_bbox(node : Mml::Node, ctx : Ctx) : BBox
      sqrt_geom(node, ctx).bbox
    end

    # ------------------------------------------------------------------
    # menclose (\boxed) — approximate: .2em padding, .067em border

    private def enclose_bbox(node : Mml::Node, ctx : Ctx) : BBox
      b = list_bbox(node.children, ctx)
      pad = 0.2 * ctx.scale
      t = 0.067 * ctx.scale
      b.w += 2 * (pad + t)
      b.h += pad + t
      b.d += pad + t
      b
    end

    # ------------------------------------------------------------------
    # mtable — approximate layout (v3 mtable port pending)

    # v3 mtable layout (common/Wrappers/mtable.js): natural column widths,
    # per-row H/D with the .75/.25 useHeight minimums, half row/column
    # spacing from the rowspacing/columnspacing attributes, axis-centered
    # bbox by default.
    record TableLayout, cells : Array(Array(BBox)), widths : Array(Float64),
                         row_h : Array(Float64), row_d : Array(Float64),
                         c_half : Array(Float64), r_half : Array(Float64),
                         col_align : Array(String), box : BBox, tctx : Ctx

    # rowspacing/columnspacing array -> ems, padded by repeating the last
    # entry and cut to `count` (v3 getRowAttributes/getColumnAttributes)
    private def table_attr_list(node : Mml::Node, name : String,
                                count : Int32) : Array(Float64)
      return [] of Float64 if count <= 0
      raw = node[name]?
      vals = if raw
        raw.split(/\s+/).reject(&.empty?).map { |p| length2em(p, 0.0) }
      else
        [] of Float64
      end
      vals << 0.0 if vals.empty?
      while vals.size < count
        vals << vals.last
      end
      vals[0, count]
    end

    private def table_col_aligns(node : Mml::Node, count : Int32) : Array(String)
      return ["center"] * count if count <= 0
      raw = node["columnalign"]?
      parts = raw ? raw.split(/\s+/).reject(&.empty?) : ["center"]
      while parts.size < count
        parts << parts.last
      end
      parts[0, count]
    end

    private def table_layout(node : Mml::Node, ctx : Ctx) : TableLayout
      rows = node.children
      num_rows = rows.size
      num_cols = rows.empty? ? 0 : rows.max_of(&.children.size)
      c_space = table_attr_list(node, "columnspacing", num_cols - 1)
      r_space = table_attr_list(node, "rowspacing", num_rows - 1)
      col_align = table_col_aligns(node, num_cols)
      c_half = [0.0] + c_space.map { |s| s / 2 } + [0.0]
      r_half = [0.0] + r_space.map { |s| s / 2 } + [0.0]

      display = case node["displaystyle"]?
                when "true"  then true
                when "false" then false
                else              ctx.display
                end
      tctx = Ctx.new(display, ctx.level, ctx.prime)

      cells = [] of Array(BBox)
      widths = Array.new(num_cols, 0.0)
      row_h = Array.new(num_rows, 0.0)
      row_d = Array.new(num_rows, 0.0)
      rows.each_with_index do |row, ri|
        cb = [] of BBox
        row.children.each_with_index do |cell, ci|
          b = list_bbox(cell.children, tctx)
          cb << b
          widths[ci] = b.w if b.w > widths[ci]
          # v3 useHeight minimums per cell
          h = {b.h, 0.75}.max
          d = {b.d, 0.25}.max
          row_h[ri] = h if h > row_h[ri]
          row_d[ri] = d if d > row_d[ri]
        end
        cells << cb
      end

      box = BBox.new
      box.w = widths.sum + c_space.sum
      height = row_h.each_with_index.sum { |h, i| h + row_d[i] } + r_space.sum
      h2 = height / 2
      box.h, box.d = case (node["align"]? || "axis").split(/\s+/).first
                     when "top"    then {height, 0.0}
                     when "bottom" then {0.0, height}
                     when "axis"   then {h2 + AXIS, h2 - AXIS}
                     else               {h2, h2}
                     end
      TableLayout.new(cells, widths, row_h, row_d, c_half, r_half, col_align,
                      box, tctx)
    end

    private def table_bbox(node : Mml::Node, ctx : Ctx) : BBox
      table_layout(node, ctx).box
    end


    # ------------------------------------------------------------------
    # Draw pass (mirrors compute_bbox; y-up coordinates)

    private def draw_node(node : Mml::Node, x : Float64, y : Float64, ctx : Ctx) : Nil
      case node.kind
      when "mi", "mn", "mtext", "ms"
        face, variant = face_variant_of(node)
        cx = x
        node.text.to_s.each_char do |ch|
          cp = remap_cp(variant, ch.ord)
          if g = glyph_of(face, cp)
            use_glyph(face, cp, cx, y, ctx.scale)
            cx += g.w * ctx.scale
          end
        end
      when "mo"
        draw_mo(node, x, y, ctx)
      when "mspace"
        # draws nothing
      when "mstyle"
        sctx = style_ctx(node, ctx)
        draw_list(node.children, x, y, sctx)
      when "mpadded", "mphantom"
        draw_list(node.children, x, y, ctx) unless node.kind == "mphantom"
      when "mfrac"
        g = frac_geom(node, ctx)
        draw_node(node.children[0], x + g.num_x, y + g.num_y, g.nctx)
        draw_node(node.children[1], x + g.den_x, y + g.den_y, g.dctx)
        if g.t > 0
          rect(x + NULLELIM * g.nctx.scale, y + AXIS * g.nctx.scale - g.t / 2,
               g.rect_w, g.t)
        end
      when "msub", "msup", "msubsup",
           "munder", "mover", "munderover"
        draw_scripts(node, x, y, ctx)
      when "msqrt", "mroot"
        draw_sqrt(node, x, y, ctx)
      when "mtable"
        draw_table(node, x, y, ctx)
      when "menclose"
        pad = 0.2 * ctx.scale
        t = 0.067 * ctx.scale
        b = bbox_of(node, ctx)
        cx = x
        node.children.each do |c|
          cb = bbox_of(c, ctx)
          draw_node(c, cx + cb.l + pad + t, y, ctx)
          cx += cb.l + cb.w + cb.r
        end
        bw = b.w - t
        rect(x + t / 2, y + b.h - t / 2, bw, t)
        rect(x + t / 2, y - b.d, bw, t)
        rect(x + t / 2, y - b.d, t, b.h + b.d)
        rect(x + b.w - t / 2, y - b.d, t, b.h + b.d)
      else
        draw_list(node.children, x, y, ctx)
      end
    end

    private def draw_list(nodes : Array(Mml::Node), x : Float64, y : Float64,
                          ctx : Ctx) : Nil
      cx = x
      nodes.each do |c|
        b = bbox_of(c, ctx)
        draw_node(c, cx + b.l, y, ctx)
        cx += b.l + b.w + b.r
      end
    end

    private def style_ctx(node : Mml::Node, ctx : Ctx) : Ctx
      display = case node["displaystyle"]?
                when "true"  then true
                when "false" then false
                else              ctx.display
                end
      level = node["scriptlevel"]?.try(&.to_i?) || ctx.level
      Ctx.new(display, level)
    end

    private def style_bbox(node : Mml::Node, ctx : Ctx) : BBox
      list_bbox(node.children, style_ctx(node, ctx))
    end

    # ------------------------------------------------------------------
    # mo draw

    private def draw_mo(node : Mml::Node, x : Float64, y : Float64, ctx : Ctx) : Nil
      return if node.text.to_s.empty?
      box = bbox_of(node, ctx) # ensures mo_info resolved
      info = @mo_info[node].not_nil!
      if info.size >= 0
        use_glyph(info.face, info.cp, x + info.accent_off, y + info.center_off,
                  ctx.scale)
      elsif info.wh.try(&.size) == 2
        draw_piecewise_v(info, x, y, box, ctx)
      else
        draw_piecewise_h(info, x, y, ctx)
      end
    end

    # v3 svg mo.js stretchVertical — all piece metrics in local ems.
    private def draw_piecewise_v(info : MoInfo, x : Float64, y : Float64,
                                 box : BBox, ctx : Ctx) : Nil
      delim = Fonts::TexPaths::DELIMITERS[info.cp].not_nil!
      pieces = delim.stretch
      top_cp, ext_cp, bot_cp, mid_cp = pieces[0]?, pieces[1]?, pieces[2]?, pieces[3]?
      top = top_cp ? glyph_of(stretch_variant_face(delim, 0), top_cp) : nil
      top_face = top_cp ? stretch_variant_face(delim, 0) : "N"
      ext = ext_cp ? glyph_of(stretch_variant_face(delim, 1), ext_cp) : nil
      ext_face = ext_cp ? stretch_variant_face(delim, 1) : "N"
      bot = bot_cp ? glyph_of(stretch_variant_face(delim, 2), bot_cp) : nil
      bot_face = bot_cp ? stretch_variant_face(delim, 2) : "N"
      mid = mid_cp ? glyph_of(stretch_variant_face(delim, 3), mid_cp) : nil
      mid_face = mid_cp ? stretch_variant_face(delim, 3) : "N"
      w = box.w

      t_size = top ? top.not_nil!.h + top.not_nil!.d : 0.0
      b_size = bot ? bot.not_nil!.h + bot.not_nil!.d : 0.0

      if mid
        mm = mid.not_nil!
        y_mid = (mm.d - mm.h) / 2 + AXIS # local units
        h_mid = mm.h + y_mid
        d_mid = mm.d - y_mid
        add_ext_v(ext_cp, ext, ext_face, box.h, 0.0, t_size, h_mid, w, x, y)
        add_ext_v(ext_cp, ext, ext_face, 0.0, box.d, d_mid, b_size, w, x, y)
        use_glyph(mid_face, mid_cp.not_nil!, x + (w - mm.w) / 2, y + y_mid, 1.0)
      else
        add_ext_v(ext_cp, ext, ext_face, box.h, box.d, t_size, b_size, w, x, y)
      end
      if top && top_cp
        tg = top.not_nil!
        use_glyph(top_face, top_cp, x + (w - tg.w) / 2, y + box.h - tg.h, 1.0)
      end
      if bot && bot_cp
        bg = bot.not_nil!
        use_glyph(bot_face, bot_cp, x + (w - bg.w) / 2, y - (box.d - bg.d), 1.0)
      end
    end

    # v3 addExtV: nested <svg> with a vertically scaled ext glyph.
    # h/d/t_size/b_size/w in local ems; (x, y) is the mo origin.
    private def add_ext_v(ext_cp : Int32?, ext : BBox?, ext_face : String,
                          h : Float64, d : Float64, t_size : Float64,
                          b_size : Float64, w : Float64, x : Float64,
                          y : Float64) : Nil
      return unless ext && ext_cp
      eh = ext.not_nil!.h
      ed = ext.not_nil!.d
      ew = ext.not_nil!.w
      t_eff = {0.0, t_size - VFUZZ}.max
      b_eff = {0.0, b_size - VFUZZ}.max
      big_y = h + d - t_eff - b_eff
      return if big_y <= 0
      s = 1.5 * big_y / (eh + ed)
      y_vb = (s * (eh - ed) - big_y) / 2
      gx = x + (w - ew) / 2
      gy = y + (b_eff - d)
      view = "0 #{fmt(y_vb * 1000)} #{fmt(ew * 1000)} #{fmt(big_y * 1000)}"
      use_svg_piece(ext_face, ext_cp.not_nil!, gx, gy, ew, big_y, view,
                    "1,#{fmt3(s)}")
    end

    # v3 stretchHorizontal
    private def draw_piecewise_h(info : MoInfo, x : Float64, y : Float64,
                                 ctx : Ctx) : Nil
      delim = Fonts::TexPaths::DELIMITERS[info.cp].not_nil!
      pieces = delim.stretch
      left_cp, ext_cp, right_cp, mid_cp = pieces[0]?, pieces[1]?, pieces[2]?, pieces[3]?
      left = left_cp ? glyph_of(stretch_variant_face(delim, 0), left_cp) : nil
      left_face = left_cp ? stretch_variant_face(delim, 0) : "N"
      ext = ext_cp ? glyph_of(stretch_variant_face(delim, 1), ext_cp) : nil
      ext_face = ext_cp ? stretch_variant_face(delim, 1) : "N"
      right = right_cp ? glyph_of(stretch_variant_face(delim, 2), right_cp) : nil
      right_face = right_cp ? stretch_variant_face(delim, 2) : "N"
      mid = mid_cp ? glyph_of(stretch_variant_face(delim, 3), mid_cp) : nil
      mid_face = mid_cp ? stretch_variant_face(delim, 3) : "N"
      w = info.d_clamped

      l_size = left ? left.not_nil!.w : 0.0
      r_size = right ? right.not_nil!.w : 0.0
      if mid
        mw = mid.not_nil!.w
        x1 = (w - mw) / 2
        x2 = (w + mw) / 2
        add_ext_h(ext_cp, ext, ext_face, w / 2, l_size, w / 2 - x1, x, y)
        add_ext_h(ext_cp, ext, ext_face, w / 2, x2 - w / 2, r_size, x + x2 - w / 2, y)
        use_glyph(mid_face, mid_cp.not_nil!, x + x1, y, 1.0)
      else
        add_ext_h(ext_cp, ext, ext_face, w, l_size, r_size, x, y)
      end
      use_glyph(left_face, left_cp.not_nil!, x, y, 1.0) if left && left_cp
      if right && right_cp
        use_glyph(right_face, right_cp.not_nil!,
                  x + w - right.not_nil!.w, y, 1.0)
      end
    end

    private def add_ext_h(ext_cp : Int32?, ext : BBox?, ext_face : String,
                          w : Float64, l_size : Float64, r_size : Float64,
                          x : Float64, y : Float64) : Nil
      return unless ext && ext_cp
      eh = ext.not_nil!.h
      ed = ext.not_nil!.d
      ew = ext.not_nil!.w
      l_eff = {0.0, l_size - HFUZZ}.max
      r_eff = {0.0, r_size - HFUZZ}.max
      big_x = w - l_eff - r_eff
      return if big_x <= 0
      s = 1.5 * (big_x / ew)
      big_y = eh + ed + 2 * VFUZZ
      d_dn = -(ed + VFUZZ)
      view = "#{fmt((s * ew - big_x) / 2 * 1000)} #{fmt(d_dn * 1000)} #{fmt(big_x * 1000)} #{fmt(big_y * 1000)}"
      use_svg_piece(ext_face, ext_cp.not_nil!, x + l_eff, y + d_dn,
                    big_x, big_y, view, "#{fmt3(s)},1")
    end

    # ------------------------------------------------------------------
    # scripts / underover draw

    private def draw_scripts(node : Mml::Node, x : Float64, y : Float64,
                             ctx : Ctx) : Nil
      if node.kind.in?({"munder", "mover", "munderover"}) &&
         !(!ctx.display && movable_limits?(node))
        g = underover_geom(node, ctx)
        children = node.children
        draw_node(children[0], x + g.base_x, y, ctx)
        if node.kind != "mover" && children.size > 1
          uc = Ctx.new(false, accent_of(children[1]?, "accentunder") ? ctx.level : ctx.level + 1, true)
          draw_node(children[1], x + g.under_x, y + g.under_y, uc)
        end
        oc = node.kind == "mover" ? children[1]? : children[2]?
        if oc
          octx = Ctx.new(false, accent_of(oc, "accent") ? ctx.level : ctx.level + 1, ctx.prime)
          draw_node(oc, x + g.over_x, y + g.over_y, octx)
        end
      else
        g = script_geom(node, ctx)
        children = node.children
        draw_node(children[0], x, y, ctx)
        sub = case node.kind
              when "msub", "munder", "msubsup", "munderover" then children[1]?
              else nil
              end
        sup = case node.kind
              when "msup", "mover"                      then children[1]?
              when "msubsup", "munderover"              then children[2]?
              else nil
              end
        if sub
          draw_node(sub, x + g.sub_x, y + g.sub_y, Ctx.new(false, ctx.level + 1, true))
        end
        if sup
          draw_node(sup, x + g.sup_x, y + g.sup_y, Ctx.new(false, ctx.level + 1, ctx.prime))
        end
      end
    end

    # ------------------------------------------------------------------
    # msqrt / mroot draw

    private def draw_sqrt(node : Mml::Node, x : Float64, y : Float64,
                          ctx : Ctx) : Nil
      g = sqrt_geom(node, ctx)
      draw_node(g.base, x + g.base_x, y, g.base_ctx)
      if r = g.root
        draw_node(r, x + g.root_x, y + g.root_y, g.root_ctx)
      end
      if g.surd_size >= 0
        use_glyph(g.surd_face, g.surd_cp, x + g.x, y + g.surd_y, ctx.scale)
      else
        draw_surd_piecewise(g, x, y, ctx)
      end
      rect(x + g.rule_x, y + g.rule_y, g.rule_w, RULE * ctx.scale)
    end

    # The stretched radical: top glyph + vertical ext (svg mo.js structure).
    private def draw_surd_piecewise(g : SqrtGeom, x : Float64, y : Float64,
                                    ctx : Ctx) : Nil
      delim = Fonts::TexPaths::DELIMITERS[0x221A].not_nil!
      pieces = delim.stretch
      top_cp = pieces[0]?
      ext_cp = pieces[1]?
      bot_cp = pieces[2]?
      top = top_cp ? glyph_of(stretch_variant_face(delim, 0), top_cp) : nil
      top_face = top_cp ? stretch_variant_face(delim, 0) : "N"
      ext = ext_cp ? glyph_of(stretch_variant_face(delim, 1), ext_cp) : nil
      ext_face = ext_cp ? stretch_variant_face(delim, 1) : "N"
      bot = bot_cp ? glyph_of(stretch_variant_face(delim, 2), bot_cp) : nil
      bot_face = bot_cp ? stretch_variant_face(delim, 2) : "N"
      w = (delim.hdw ? delim.hdw[2] : 0.5)

      t_size = top ? top.not_nil!.h + top.not_nil!.d : 0.0
      b_size = bot ? bot.not_nil!.h + bot.not_nil!.d : 0.0
      h = g.bbox.h - RULE * ctx.scale
      add_ext_v(ext_cp, ext, ext_face, h, 0.0, t_size, b_size, w, x + g.x, y + g.surd_y)
      if top && top_cp
        tg = top.not_nil!
        use_glyph(top_face, top_cp, x + g.x + (w - tg.w) / 2,
                  y + g.surd_y + h - tg.h, 1.0)
      end
      if bot && bot_cp
        bg = bot.not_nil!
        use_glyph(bot_face, bot_cp, x + g.x + (w - bg.w) / 2,
                  y + g.surd_y, 1.0)
      end
    end

    # ------------------------------------------------------------------
    # mtable draw — approximate

    # v3 mtable placeRows/mtr.placeCells: row baselines from the top edge,
    # cells at half-spacing offsets, aligned inside their column width.
    private def draw_table(node : Mml::Node, x : Float64, y : Float64,
                           ctx : Ctx) : Nil
      lay = table_layout(node, ctx)
      yb = y + lay.box.h # top edge, y-up
      node.children.each_with_index do |row, ri|
        yb -= lay.r_half[ri] + lay.row_h[ri]
        xc = x
        row.children.each_with_index do |cell, ci|
          w = lay.widths[ci]? || 0.0
          if b = lay.cells[ri][ci]?
            off = case lay.col_align[ci]?
                  when "left"  then 0.0
                  when "right" then w - b.w
                  else              (w - b.w) / 2
                  end
            draw_list(cell.children, xc + off, yb, lay.tctx)
          end
          xc += (lay.c_half[ci]? || 0.0) + w + (lay.c_half[ci + 1]? || 0.0)
        end
        yb -= lay.row_d[ri] + (lay.r_half[ri + 1]? || 0.0)
      end
    end
  end
end
