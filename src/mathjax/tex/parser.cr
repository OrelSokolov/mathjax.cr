# Port of MathJax `input/tex/TexParser.ts` + `base/BaseMethods.ts` +
# `base/BaseItems.ts`: a recursive-descent TeX parser producing an
# `MathJax::Mml::Node` tree.
require "./symbols"
require "../mml/node"

module MathJax::TeX
  class TexError < Exception
  end

  class Parser
    record Macro, nargs : Int32, body : String

    MAX_EXPANSIONS = 1000
    MAX_DEPTH      = 50

    @pos : Int32 = 0
    @expansions : Int32 = 0
    @depth : Int32
    @force_limits : Bool? = nil
    @current_cs : String = ""
    @colors : Hash(String, String)
    @pending_func : Bool = false
    @env_depth : Int32 = 0
    @small_binom : Bool = false

    def initialize(@string : String, @display : Bool = false,
                   @macros : Hash(String, Macro) = {} of String => Macro,
                   @depth : Int32 = 0, physics : Bool = false)
      raise TexError.new("Math too deeply nested") if @depth > MAX_DEPTH
      @colors = {} of String => String
      if physics
        PHYSICS_MACROS.each { |k, m| @macros[k] = m }
      end
    end

    # ------------------------------------------------------------------
    # Entry point: full expression -> <math> node
    def parse : Mml::Node
      nodes = parse_list([:eof])
      math = Mml::Node.new("math")
      math.set("display", "block") if @display
      math.set("xmlns", "http://www.w3.org/1998/Math/MathML")
      math.add(nodes.size == 1 ? nodes.first : Mml::Node.new("mrow").tap { |r| r.children.concat(nodes) })
      math
    end

    # ------------------------------------------------------------------
    # Character-level helpers

    private def cur : Char?
      @pos < @string.size ? @string[@pos] : nil
    end

    private def cur_at(offset : Int32) : Char?
      i = @pos + offset
      i < @string.size ? @string[i] : nil
    end

    # Skip whitespace and %-comments (ignored in math mode).
    private def skip_ws : Nil
      while c = cur
        if c.whitespace?
          @pos += 1
        elsif c == '%'
          @pos += 1
          while cur && cur != '\n'
            @pos += 1
          end
        else
          break
        end
      end
    end

    # Read a control-sequence name (backslash already consumed).
    private def read_cs : String
      rest = @string[@pos..]
      if m = rest.match(/\A[a-zA-Z]+ ?/)
        @pos += m[0].size
        m[0].strip
      elsif rest.size > 0
        @pos += 1
        rest[0].to_s
      else
        " "
      end
    end

    private def expect_char(c : Char, message : String) : Nil
      skip_ws
      if cur == c
        @pos += 1
      else
        raise TexError.new(message)
      end
    end

    # Port of TexParser#getArgument: a raw string argument.
    private def get_arg(name : String, none_ok = false) : String?
      skip_ws
      c = cur
      if c.nil? || c == '}'
        return nil if none_ok
        raise TexError.new(c.nil? ? "Missing argument for \\#{name}" : "Extra close brace or missing open brace")
      end
      if c == '\\'
        @pos += 1
        return "\\" + read_cs
      end
      if c == '{'
        j = @pos + 1
        @pos += 1
        parens = 1
        while @pos < @string.size
          case @string[@pos]
          when '\\'  then @pos += 2
          when '{'   then parens += 1; @pos += 1
          when '}'
            parens -= 1
            if parens == 0
              s = @string[j...@pos]
              @pos += 1
              return s
            end
            @pos += 1
          else @pos += 1
          end
        end
        raise TexError.new("Missing close brace")
      end
      @pos += 1
      c.to_s
    end

    # Port of TexParser#getBrackets: an optional [...] argument.
    private def get_brackets(default : String? = nil) : String?
      skip_ws
      return default unless cur == '['
      @pos += 1
      j = @pos
      braces = 0
      while @pos < @string.size
        c = @string[@pos]
        if c == '\\'
          @pos += 2
          next
        elsif c == '{'
          braces += 1
        elsif c == '}'
          braces -= 1
        elsif c == ']' && braces == 0
          break
        end
        @pos += 1
      end
      raise TexError.new("Missing close bracket") unless cur == ']'
      result = @string[j...@pos]
      @pos += 1
      result
    end

    # ------------------------------------------------------------------
    # Stop-condition handling for group parsing

    private def stopper_at(stop : Array(Symbol)) : Symbol?
      c = cur
      return :eof if c.nil? && stop.includes?(:eof)
      return nil if c.nil?
      case c
      when '}' then stop.includes?(:rbrace) ? :rbrace : nil
      when '&' then stop.includes?(:amp) ? :amp : nil
      when '\\'
        save = @pos
        @pos += 1
        cs = read_cs
        @pos = save
        if cs == "\\"
          stop.includes?(:newline) ? :newline : nil
        elsif cs == "right"
          stop.includes?(:right) ? :right : nil
        elsif cs == "end"
          stop.includes?(:end) ? :end : nil
        else
          nil
        end
      else nil
      end
    end

    # ------------------------------------------------------------------
    # Core parser

    # Parse a sequence of nodes until one of `stop` appears (unconsumed).
    protected def parse_list(stop : Array(Symbol)) : Array(Mml::Node)
      nodes = [] of Mml::Node
      loop do
        skip_ws
        break if stopper_at(stop)
        c = cur
        raise TexError.new("Unexpected end of input") unless c
        case c
        when '{'
          @pos += 1
          inner = parse_list([:rbrace])
          expect_char('}', "Missing close brace")
          nodes << Mml::Node.new("mrow").tap { |r| r.children.concat(inner) }
        when '}'
          raise TexError.new("Extra close brace or missing open brace")
        when '&'
          raise TexError.new("Misplaced &")
        when '^', '_', '\''
          base = nodes.pop? || Mml::Node.new("mi")
          nodes << parse_scripts(base)
          if @pending_func
            nodes << Mml::Node.leaf("mo", "\u2061")
            @pending_func = false
          end
        when '\\'
          if infix = peek_infix_cs
            # Generalized fractions: {num \over den} — numerator is
            # everything collected so far, denominator is the rest of
            # the current group.
            num = Mml::Node.new("mrow").tap { |r| r.children.concat(nodes) }
            return [make_infix_frac(infix, num, stop)]
          end
          handle_cs(stop).each do |n|
            # MathJax merges repeated arrow operators: \uparrow\uparrow -> ↑↑
            if n.kind == "mo" && (t = n.text) && ARROW_MERGE.any? { |a| t == a } &&
               (prev = nodes.last?) && prev.kind == "mo" &&
               (pt = prev.text) && ARROW_MERGE.any? { |a| pt.starts_with?(a) } &&
               n.attributes.empty?
              prev.text = pt + t
            else
              nodes << n
            end
          end
          if @pending_func && !script_follows?
            nodes << Mml::Node.leaf("mo", "\u2061")
            @pending_func = false
          end
        else
          nodes.concat(next_char_nodes)
        end
      end
      nodes
    end

    # If the control sequence at the current position is an infix
    # fraction operator, consume it and return its name.
    private def peek_infix_cs : String?
      return nil unless cur == '\\'
      save = @pos
      @pos += 1
      cs = read_cs
      if INFIX_FRACS.includes?(cs)
        cs
      else
        @pos = save
        nil
      end
    end

    # Consume one character (or number run) -> leaf nodes.
    # MathJax remaps '-' to the minus sign (U+2212) in math mode.
    private def math_char(c : Char) : Mml::Node
      if c == '-'
        Mml::Node.leaf("mo", "−")
      elsif c == '*'
        Mml::Node.leaf("mo", "∗")
      elsif c.number?
        Mml::Node.leaf("mn", c.to_s)
      elsif c.letter?
        Mml::Node.leaf("mi", c.to_s)
      else
        Mml::Node.leaf("mo", c.to_s)
      end
    end

    private def next_char_nodes : Array(Mml::Node)
      c = cur.not_nil!
      if c == '~'
        @pos += 1
        return [Mml::Node.leaf("mtext", "\u00A0")]
      end
      if c.number? || (c == '.' && (@string[@pos + 1]? || ' ').number?)
        start = @pos
        @pos += 1
        # \d+(\.\d*)? maximal munch: one dot allowed, a second dot ends the
        # run; {,} inside a number (thousands separator) joins the run.
        dot_used = false
        loop do
          n = cur
          if n && n.number?
            @pos += 1
          elsif n == '.' && !dot_used
            dot_used = true
            @pos += 1
          elsif n == '{' && cur_at(1) == ',' && cur_at(2) == '}'
            @pos += 3
          else
            break
          end
        end
        return [Mml::Node.leaf("mn", @string[start...@pos].gsub("{,}", ","))]
      end
      # MathJax tokenizes ':=' as a single operator.
      if c == ':' && cur_at(1) == '='
        @pos += 2
        return [Mml::Node.leaf("mo", ":=")]
      end
      @pos += 1
      [math_char(c)]
    end

    # Parse a single TeX argument (group or single token) -> node list.
    private def parse_arg_nodes(name : String) : Array(Mml::Node)
      skip_ws
      c = cur
      raise TexError.new("Missing argument for \\#{name}") if c.nil?
      if c == '{'
        @pos += 1
        inner = parse_list([:rbrace])
        expect_char('}', "Missing close brace")
        inner
      elsif c == '\\'
        handle_cs(stop_of(:eof))
      else
        # A single TeX token: exactly one character.
        @pos += 1
        [math_char(c)]
      end
    end

    private def stop_of(*syms : Symbol) : Array(Symbol)
      syms.to_a
    end

    # A single node for scripts/directives: wrap multiple children in mrow.
    private def single_arg_node(name : String) : Mml::Node
      nodes = parse_arg_nodes(name)
      nodes.size == 1 ? nodes.first : Mml::Node.new("mrow").tap { |r| r.children.concat(nodes) }
    end

    # ------------------------------------------------------------------
    # Sub/superscripts, primes

    private def parse_scripts(base : Mml::Node) : Mml::Node
      sub = nil
      sup = nil
      loop do
        c = cur
        case c
        when '\''
          n = 0
          while cur == '\''
            n += 1
            @pos += 1
          end
          raise TexError.new("Double superscript") if sup
          sup = Mml::Node.leaf("mo", prime_text(n))
        when '^'
          raise TexError.new("Double superscript") if sup
          @pos += 1
          sup = single_arg_node("superscript")
        when '_'
          raise TexError.new("Double subscript") if sub
          @pos += 1
          sub = single_arg_node("subscript")
        else break
        end
        skip_ws
      end
      return base unless sub || sup

      under_over = under_over?(base)
      @force_limits = nil
      if sub && sup
        node = Mml::Node.new(under_over ? "munderover" : "msubsup")
        node.add(base).add(sub.not_nil!).add(sup.not_nil!)
      elsif sub
        node = Mml::Node.new(under_over ? "munder" : "msub")
        node.add(base).add(sub.not_nil!)
      else
        node = Mml::Node.new(under_over ? "mover" : "msup")
        node.add(base).add(sup.not_nil!)
      end
      node
    end

    private def prime_text(n : Int32) : String
      case n
      when 1 then "′"
      when 2 then "″"
      when 3 then "‴"
      when 4 then "⁗"
      else    "′" * n
      end
    end

    # Should scripts on `base` become under/over?
    # MathJax uses munderover for big ops with movable limits even inline,
    # and stacks scripts on accent/brace bases (munder/mover) as well.
    private def under_over?(base : Mml::Node) : Bool
      unless @force_limits.nil?
        return @force_limits.not_nil!
      end
      return true if base.kind.in?("munder", "mover", "munderover") &&
                     (script = base.children.last?) && script.kind == "mo" &&
                     script.text.in?("⏞", "⏟")
      text = base.text
      return false unless text
      if (base.kind == "mi" || base.kind == "mo") && Symbols::LIM_FUNCS.includes?(text)
        return true
      end
      if base.kind == "mo" && Symbols::BIG_OPS.any? { |k| Symbols::CHARS[k]? == text }
        return true
      end
      false
    end

    # ------------------------------------------------------------------
    # Control sequences

    private def handle_cs(stop : Array(Symbol)) : Array(Mml::Node)
      @pos += 1 # consume backslash
      cs = read_cs
      cs = Symbols::ALIASES[cs]? || cs
      @current_cs = cs

      # User-defined macros (highest priority).
      if user_macro = @macros[cs]?
        expand_macro(user_macro)
        return [] of Mml::Node
      end

      case cs
      when "\\"          then raise TexError.new("Misplaced \\")
      when "right"       then raise TexError.new("Misplaced \\right")
      when "end"         then raise TexError.new("Misplaced \\end")
      when "frac", "dfrac", "tfrac", "cfrac" then [make_frac(cs)]
      when "binom", "dbinom", "tbinom"       then [make_binom(cs)]
      when "genfrac"                          then [make_genfrac]
      when "middle"                           then [make_middle]
      when "sqrt"        then [make_sqrt]
      when "left"        then parse_left_right
      when "begin"       then parse_environment
      when "stackrel", "overset", "underset" then [make_stackrel(cs)]
      when "overbrace", "underbrace"         then [make_brace(cs)]
      when "quad"        then [space("1em")]
      when "qquad"       then [space("2em")]
      when "enspace"     then [space("0.5em")]
      when "thinspace", ","        then [space("0.167em")]
      when "medspace", ":"         then [space("0.222em")]
      when "thickspace", ";"       then [space("0.278em")]
      when " "                    then [Mml::Node.leaf("mtext", "\u00A0")]
      when "negthinspace", "!"    then [space("-0.167em")]
      when "negmedspace"           then [space("-0.222em")]
      when "negthickspace"         then [space("-0.278em")]
      when "displaystyle"          then [style_rest(stop, displaystyle: "true")]
      when "textstyle"             then [style_rest(stop, displaystyle: "false")]
      when "scriptstyle"           then [style_rest(stop, scriptlevel: "1")]
      when "scriptscriptstyle"     then [style_rest(stop, scriptlevel: "2")]
      when "def"                   then handle_def(false)
      when "newcommand", "renewcommand" then handle_def(true)
      when "limits"                then @force_limits = true; [] of Mml::Node
      when "nolimits"              then @force_limits = false; [] of Mml::Node
      when "not"
        make_not
      when "dots"
        # amsmath-style smart dots: cdots before an operator, ldots otherwise.
        skip_ws
        c = cur
        char = (c && c.in?('+', '-', '=', '<', '>')) ? "⋯" : "…"
        [Mml::Node.leaf("mo", char)]
      when "color"                 then [color_rest(stop)]
      when "textcolor"             then [make_textcolor]
      when "definecolor"           then handle_definecolor
      when "colorbox"              then [make_colorbox]
      when "fcolorbox"             then [make_fcolorbox]
      when "cancel"                then [make_cancel("updiagonalstrike")]
      when "bcancel"               then [make_cancel("downdiagonalstrike")]
      when "xcancel"               then [make_cancel("updiagonalstrike downdiagonalstrike")]
      when "sout"                  then [make_cancel("horizontalstrike")]
      when "phantom", "hphantom", "vphantom" then [wrap("mphantom", parse_arg_nodes(cs))]
      when "boxed"                 then [wrap("menclose", parse_arg_nodes(cs)).set("notation", "box")]
      when "vec", "hat", "bar", "tilde", "dot", "ddot", "breve", "check",
           "acute", "grave", "mathring", "widehat", "widetilde",
           "overline", "underline", "overrightarrow", "overleftarrow"
        [make_accent(cs)]
      when "text", "textrm", "textit", "textbf", "textsf", "texttt", "textnormal"
        [make_text(cs)]
      when "big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl",
           "bigr", "Bigr", "biggr", "Biggr", "bigm", "Bigm", "biggm", "Biggm"
        [make_bigdelim(cs)]
      when "pmod" then make_pmod(true)
      when "bmod" then [Mml::Node.leaf("mo", "mod")]
      when "mod"  then [Mml::Node.leaf("mo", "mod"), space("0.333em")]
      when "operatorname", "operatorname*"
        [apply_font_group(parse_arg_nodes(cs), "normal").first? || Mml::Node.new("mrow")]
      when "rm", "bf", "it", "sf", "tt", "cal", "scr", "frak", "mit"
        # Old-style font switches apply to the rest of the current group.
        variant = {"rm" => "normal", "bf" => "bold", "it" => "italic",
                   "sf" => "sans-serif", "tt" => "monospace",
                   "cal" => "script", "scr" => "script",
                   "frak" => "fraktur", "mit" => "italic"}[cs]
        [wrap("mrow", apply_font_group(parse_list(stop), variant, merge: false))]
      else
        if Symbols::FONT_VARIANTS.has_key?(cs)
          variant = Symbols::FONT_VARIANTS[cs]
          arg = get_arg(cs).not_nil!
          apply_font_group(sub_parse(arg), variant)
        elsif Symbols::FUNCS.includes?(cs)
          # Multi-char mi renders upright by default; the invisible
          # function-application operator is appended after any scripts
          # (\cos^2 -> msup + 2061, not msup(2061)).
          @pending_func = true
          [Mml::Node.leaf("mi", cs)]
        elsif Symbols::LIM_FUNCS.includes?(cs)
          [Mml::Node.leaf("mo", cs)]
        elsif char = Symbols::CHARS[cs]?
          if Symbols::ESCAPED_LITERALS.includes?(cs)
            # Escaped literals like \& are ordinary identifiers in MathJax.
            [Mml::Node.leaf("mi", char).set("mathvariant", "normal")]
          else
            kind = Symbols::LETTERS.includes?(cs) ? "mi" : "mo"
            node = Mml::Node.leaf(kind, char)
            # Uppercase greek and letter-like operators are upright in MathJax.
            node.set("mathvariant", "normal") if Symbols::UPRIGHT.includes?(cs)
            [node]
          end
        else
          raise TexError.new("Undefined control sequence: \\#{cs}")
        end
      end
    end

    # \not\in -> ∉ (merged), bare \not -> combining slash.
    private def make_not : Array(Mml::Node)
      skip_ws
      if cur == '\\'
        save = @pos
        @pos += 1
        cs = read_cs
        if merged = Symbols::NOT_MERGE[cs]?
          return [Mml::Node.leaf("mo", merged)]
        end
        @pos = save
      end
      [Mml::Node.leaf("mo", "̸")]
    end

    private def space(width : String) : Mml::Node
      Mml::Node.new("mspace").set("width", width)
    end

    private def wrap(kind : String, nodes : Array(Mml::Node)) : Mml::Node
      Mml::Node.new(kind).tap { |n| n.children.concat(nodes) }
    end

    # ------------------------------------------------------------------
    # Font application (port of how MathJax puts mathvariant on tokens)

    # Apply a font variant to a node list. With merge=true consecutive
    # single-letter mi's fuse into one run (\mathrm{onions} -> one mi);
    # old-style switches (\rm ISCO) keep separate letters.
    private def apply_font_group(nodes : Array(Mml::Node), variant : String, merge : Bool = true) : Array(Mml::Node)
      result = [] of Mml::Node
      run = ""
      flush = ->do
        unless run.empty?
          mi = Mml::Node.leaf("mi", run)
          if run.chars.all?(&.ascii_letter?)
            mi.set("mathvariant", variant) unless variant == "normal" && run.size > 1
          end
          result << mi
          run = ""
        end
      end
      nodes.each do |node|
        if merge && node.kind == "mi" && (t = node.text) && t.size == 1 && t[0].letter? && node.attributes.empty?
          run += t
          next
        end
        # \mathrm{CO_2}: attach script to the accumulated letter run
        # (msub(mi "CO", 2), not msub(mi "O", 2)).
        if merge && !run.empty? && node.kind.in?("msub", "msup", "msubsup") &&
           (base = node.children.first?) && base.kind == "mi" &&
           (bt = base.text) && bt.size == 1 && bt[0].ascii_letter? && base.attributes.empty?
          base.text = run + bt
          base.set("mathvariant", variant) unless variant == "normal"
          run = ""
          node.children.skip(1).each { |c| apply_font_node(c, variant) }
          result << node
          next
        end
        flush.call
        apply_font_node(node, variant)
        result << node
      end
      flush.call
      result
    end

    private def apply_font_node(node : Mml::Node, variant : String) : Nil
      case node.kind
      when "mi"
        # MathJax restyles latin letters with any font command, and greek
        # letters with sans-serif only (\mathbf{\tau} stays plain,
        # \mathsf{\Theta} becomes sans-serif).
        t = node.text
        if t && (t.chars.all?(&.ascii_letter?) || variant == "sans-serif")
          if variant != "normal" || t.size == 1
            node.set("mathvariant", variant)
          end
        end
      when "mtext"
        node.set("mathvariant", variant) unless variant == "normal"
      when "mn"
        # \bf bolds digits (dataset-backed); most variants leave numbers alone.
        node.set("mathvariant", variant) if variant == "bold"
      when "mo"
        # Italic styles reach operators (\mathit{CG(F)} italicizes parens).
        node.set("mathvariant", variant) if variant == "italic"
      else
        node.children.each { |c| apply_font_node(c, variant) }
      end
    end

    # \big(, \Big[, ... -> <mo minsize maxsize> (MathJax delimiter sizes)
    BIG_SIZES = {"big" => "1.2em", "Big" => "1.623em", "bigg" => "2.047em", "Bigg" => "2.47em"}

    private def make_bigdelim(cs : String) : Mml::Node
      base = cs.chomp("l").chomp("r").chomp("m")
      size = BIG_SIZES[base]? || "1.2em"
      char = get_delim(cs)
      Mml::Node.leaf("mo", char).set("minsize", size).set("maxsize", size)
    end

    # \pmod{m}: mspace 1em ( mod mspace m )
    private def make_pmod(with_parens : Bool) : Array(Mml::Node)
      arg = parse_arg_nodes("pmod")
      if with_parens
        [space("1em"),
         Mml::Node.leaf("mo", "("),
         Mml::Node.leaf("mi", "mod"),
         space("0.333em")] + arg + [Mml::Node.leaf("mo", ")")]
      else
        [space("1em"), Mml::Node.leaf("mi", "mod"), space("0.333em")] + arg
      end
    end

    # ------------------------------------------------------------------
    # \frac \sqrt \binom ...

    private def make_frac(cs : String) : Mml::Node
      was_small = @small_binom
      @small_binom = true
      num = single_arg_node(cs)
      den = single_arg_node(cs)
      @small_binom = was_small
      case cs
      when "dfrac" then wrap("mstyle", [Mml::Node.new("mfrac").add(num).add(den)]).set("displaystyle", "true")
      when "tfrac" then wrap("mstyle", [Mml::Node.new("mfrac").add(num).add(den)]).set("displaystyle", "false")
      when "cfrac"
        # MathJax's \cfrac pads each argument with an empty mpadded.
        pad = Mml::Node.new("mpadded").set("width", "0")
        Mml::Node.new("mfrac")
          .add(Mml::Node.new("mpadded").set("width", "0"))
          .add(num)
          .add(Mml::Node.new("mpadded").set("width", "0"))
          .add(den)
      else Mml::Node.new("mfrac").add(num).add(den)
      end
    end

    # ------------------------------------------------------------------
    # Generalized (infix) fractions: a \over b, a \atop b, a \choose b, ...

    INFIX_FRACS = {"over", "atop", "choose", "above",
                   "overwithdelims", "atopwithdelims", "abovewithdelims"}

    private def make_infix_frac(cs : String, num : Mml::Node, stop : Array(Symbol)) : Mml::Node
      thickness = nil
      open = ""
      close = ""
      case cs
      when "atop", "atopwithdelims" then thickness = "0"
      when "choose"                 then thickness = "0"; open = "("; close = ")"
      when "above", "abovewithdelims"
        dim = get_brackets
        thickness = dim unless dim.nil? || dim.empty?
      end
      if cs.ends_with?("withdelims")
        open = get_delim(cs) unless open.empty?
        close = get_delim(cs)
      end
      den_nodes = parse_list(stop)
      den = den_nodes.size == 1 ? den_nodes.first : Mml::Node.new("mrow").tap { |r| r.children.concat(den_nodes) }
      frac = Mml::Node.new("mfrac").add(num).add(den)
      frac.set("linethickness", thickness) if thickness
      if open.empty? && close.empty?
        frac
      else
        row = Mml::Node.new("mrow")
        row.add(fence(open, "open").not_nil!) unless open.empty?
        row.add(frac)
        row.add(fence(close, "close").not_nil!) unless close.empty?
        row
      end
    end

    # \genfrac{left}{right}{thickness}{style}{num}{den}
    private def make_genfrac : Mml::Node
      open = get_delim_arg("genfrac")
      close = get_delim_arg("genfrac")
      thickness = get_arg("genfrac").not_nil!
      style = get_arg("genfrac").not_nil!
      num = single_arg_node("genfrac")
      den = single_arg_node("genfrac")
      frac = Mml::Node.new("mfrac").add(num).add(den)
      frac.set("linethickness", thickness) unless thickness.empty?
      node = frac
      if style == "0" || style == "1" || style == "2" || style == "3"
        node = wrap("mstyle", [frac])
        node.set("displaystyle", style == "0" ? "true" : "false")
        node.set("scriptlevel", {"0" => "0", "1" => "0", "2" => "1", "3" => "2"}[style])
      end
      if open.empty? && close.empty?
        node
      else
        row = Mml::Node.new("mrow")
        row.add(fence(open, "open").not_nil!) unless open.empty?
        row.add(node)
        row.add(fence(close, "close").not_nil!) unless close.empty?
        row
      end
    end

    # A \genfrac delimiter argument: empty braces, a character or a cs name.
    private def get_delim_arg(name : String) : String
      skip_ws
      if cur == '{'
        arg = get_arg(name).not_nil!
        arg.empty? ? "" : (Symbols::DELIMITERS[arg]? || arg)
      else
        get_delim(name)
      end
    end

    # \middle used inside \left...\right
    private def make_middle : Mml::Node
      char = get_delim("middle")
      Mml::Node.leaf("mo", char).set("fence", "true").set("stretchy", "true")
    end

    private def make_binom(cs : String) : Mml::Node
      size = @small_binom ? "1.2em" : "2.047em"
      was_small = @small_binom
      @small_binom = true
      num = single_arg_node(cs)
      den = single_arg_node(cs)
      @small_binom = was_small
      inner = Mml::Node.new("mfrac").add(num).add(den).set("linethickness", "0")
      if cs == "tbinom"
        inner = wrap("mstyle", [inner]).set("displaystyle", "false")
      else
        # MathJax fences binomials with \big/\bigg-sized parens depending
        # on the surrounding script context.
        big_paren = ->(c : String) { Mml::Node.leaf("mo", c).set("minsize", size).set("maxsize", size) }
        row = Mml::Node.new("mrow")
        row.add(big_paren.call("(")).add(inner).add(big_paren.call(")"))
        row
      end
    end

    private def make_sqrt : Mml::Node
      index = get_brackets
      body = single_arg_node("sqrt")
      if index && !index.empty?
        Mml::Node.new("mroot").add(body).tap { |n| n.children.concat(sub_parse(index)) }
      else
        Mml::Node.new("msqrt").add(body)
      end
    end

    private def make_stackrel(cs : String) : Mml::Node
      first = single_arg_node(cs)
      second = single_arg_node(cs)
      case cs
      when "underset" then Mml::Node.new("munder").add(second).add(first)
      when "stackrel", "overset" then Mml::Node.new("mover").add(second).add(first)
      else raise TexError.new("unreachable")
      end
    end

    private def make_brace(cs : String) : Mml::Node
      body = single_arg_node(cs)
      if cs == "overbrace"
        Mml::Node.new("mover").add(body).add(Mml::Node.leaf("mo", "⏞"))
      else
        Mml::Node.new("munder").add(body).add(Mml::Node.leaf("mo", "⏟"))
      end
    end

    # ------------------------------------------------------------------
    # Accents: \vec \hat \overline ...

    ACCENTS = {
      "vec" => "→", "hat" => "^", "widehat" => "^", "bar" => "¯",
      "tilde" => "~", "widetilde" => "~", "dot" => "˙", "ddot" => "¨",
      "breve" => "˘", "check" => "ˇ", "acute" => "´", "grave" => "`",
      "mathring" => "˚",
    }

    private def make_accent(cs : String) : Mml::Node
      base = single_arg_node(cs)
      if char = ACCENTS[cs]?
        Mml::Node.new("mover").add(base)
          .add(Mml::Node.leaf("mo", char).set("accent", "true"))
      else
        char, stretchy = case cs
                         when "overline"        then {"―", true}
                         when "underline"       then {"_", true}
                         when "overrightarrow"  then {"→", true}
                         when "overleftarrow"   then {"←", true}
                         else raise TexError.new("unreachable")
                         end
        kind = cs == "underline" ? "munder" : "mover"
        node = Mml::Node.new(kind).add(base)
          .add(Mml::Node.leaf("mo", char).set("stretchy", "true"))
        node
      end
    end

    # ------------------------------------------------------------------
    # \left ... \right

    private def get_delim(name : String) : String
      skip_ws
      token = case cur
              when nil   then raise TexError.new("Missing delimiter for \\#{name}")
              when '\\'  then @pos += 1; cs = read_cs; cs == "|" ? "Vert" : cs
              else            c = cur.not_nil!; @pos += 1; c.to_s
              end
      Symbols::DELIMITERS[token]? || raise TexError.new("Missing or unrecognized delimiter for \\#{name}")
    end

    private def fence(char : String, side : String) : Mml::Node?
      return nil if char.empty?
      Mml::Node.leaf("mo", char).set("fence", "true").set("stretchy", "true").set("side", side)
    end

    private def parse_left_right : Array(Mml::Node)
      open = get_delim("left")
      inner = parse_list([:right])
      skip_ws
      raise TexError.new("Missing \\right") unless cur == '\\'
      @pos += 1
      read_cs # "right"
      close = get_delim("right")
      row = Mml::Node.new("mrow")
      f = fence(open, "open")
      g = fence(close, "close")
      if f || g || !inner.empty?
        row.add(f) if f
        inner.each { |n| row.add(n) }
        row.add(g) if g
        [row]
      else
        [] of Mml::Node
      end
    end

    # ------------------------------------------------------------------
    # \begin{...} ... \end{...}

    MATRIX_FENCES = {
      "pmatrix"  => {"(", ")"},
      "bmatrix"  => {"[", "]"},
      "Bmatrix"  => {"{", "}"},
      "vmatrix"  => {"|", "|"},
      "Vmatrix"  => {"‖", "‖"},
    }

    ALIGN_ENVS = {"aligned", "align", "align*", "split", "alignedat",
                  "alignat", "alignat*", "flalign", "flalign*"}

    # Operators MathJax merges when repeated.
    ARROW_MERGE = {"↑", "↓"}

    # True if a ^ _ ' follows (possibly after spaces), without consuming.
    private def script_follows? : Bool
      i = @pos
      while i < @string.size && @string[i].whitespace?
        i += 1
      end
      c = @string[i]?
      !!(c && c.in?('^', '_', '\''))
    end

    private def parse_environment : Array(Mml::Node)
      @env_depth += 1
      result = parse_environment_inner
      @env_depth -= 1
      result
    end

    private def parse_environment_inner : Array(Mml::Node)
      env = get_arg("begin").not_nil!
      columnalign = case env
                     when "cases" then nil # computed from column count below
                     when "aligned", "align", "align*", "split", "alignedat" then nil # computed below
                     when "gathered", "gather", "gather*" then "center"
                     when "array"
                       spec = get_arg("array").not_nil!
                       spec.chars.select { |c| {'l', 'c', 'r'}.includes?(c) }
                         .map { |c| {'l' => "left", 'c' => "center", 'r' => "right"}[c] }
                         .join(" ")
                     end

      rows = [] of Array(Array(Mml::Node))
      cells = [] of Array(Mml::Node)
      loop do
        cells << parse_list([:amp, :newline, :end])
        case stopper_at([:amp, :newline, :end])
        when .nil? then raise TexError.new("Missing \\end{#{env}}")
        when :amp
          @pos += 1
        when :newline
          @pos += 1 # backslash
          read_cs  # "\"
          get_brackets
          rows << cells
          cells = [] of Array(Mml::Node)
        when :end
          @pos += 1
          read_cs
          end_env = get_arg("end").not_nil!
          raise TexError.new("Mismatched \\end{#{end_env}}; expected \\end{#{env}}") unless end_env == env
          # Trailing \\ before \end produces no empty row (as in MathJax).
          rows << cells unless cells.all?(&.empty?) && !rows.empty?
          break
        when :eof then raise TexError.new("Missing \\end{#{env}}")
        end
      end

      columnalign ||= alternating_align(rows) if ALIGN_ENVS.includes?(env)

      table = Mml::Node.new("mtable")
      table.set("columnalign", columnalign) if columnalign
      if @env_depth > 1 && (env.in?(MATRIX_FENCES.keys) || env.in?({"matrix", "smallmatrix"}))
        # Nested matrices (inside another environment's cell) carry an
        # explicit center alignment; top-level ones do not.
        table.set("columnalign", "center")
      end
      rows.each do |row|
        tr = table.add("mtr")
        row.each_with_index do |cell, ci|
          mtd = tr.add("mtd")
          # MathJax's align-family empty-mi placeholder in odd cells:
          # present when the cell starts with an operator, or when the
          # preceding cell is non-empty and does not start with one.
          if ALIGN_ENVS.includes?(env) && ci.odd? &&
             (starts_operator?(cell) ||
              (!row[ci - 1].empty? && !starts_operator?(row[ci - 1])))
            mtd.add(Mml::Node.leaf("mi", ""))
          end
          mtd.children.concat(cell)
        end
      end

      if open_close = MATRIX_FENCES[env]?
        row = Mml::Node.new("mrow")
        row.add(fence(open_close[0], "open").not_nil!)
        row.add(table)
        row.add(fence(open_close[1], "close").not_nil!)
        [row]
      elsif env == "cases"
        ncols = rows.max_of(&.size)
        table.set("columnalign", (["left"] * ncols).join(" "))
        row = Mml::Node.new("mrow")
        row.add(fence("{", "open").not_nil!)
        row.add(table)
        # MathJax closes cases with an empty stretchy fence.
        row.add(Mml::Node.leaf("mo", "").set("fence", "true").set("stretchy", "true"))
        [row]
      else
        [table]
      end
    end

    # True if the cell's first node is a binary/relation operator.
    private def starts_operator?(cell : Array(Mml::Node)) : Bool
      first = cell.first?
      return false unless first && first.kind == "mo"
      {"+", "−", "-", "=", "×", "⋅", "·", "/", "<", ">", "≤", "≥"}.includes?(first.text.to_s)
    end

    private def alternating_align(rows : Array(Array(Array(Mml::Node)))) : String
      ncols = rows.max_of(&.size)
      ncols.times.map { |i| i.even? ? "right" : "left" }.join(" ")
    end

    # ------------------------------------------------------------------
    # \text and font commands

    private def make_text(cs : String) : Mml::Node
      raw = get_arg(cs).not_nil!
      node = Mml::Node.leaf("mtext", clean_text(raw))
      case cs
      when "textit"     then node.set("mathvariant", "italic")
      when "textbf"     then node.set("mathvariant", "bold")
      when "textsf"     then node.set("mathvariant", "sans-serif")
      when "texttt"     then node.set("mathvariant", "monospace")
      end
      node
    end

    # Minimal cleanup of raw text: escapes and ~ as space.
    private def clean_text(raw : String) : String
      String.build do |io|
        i = 0
        while i < raw.size
          c = raw[i]
          case c
          when '~' then io << ' '; i += 1
          when '\\'
            rest = raw[i + 1..]
            if m = rest.match(/\A[a-zA-Z]+/)
              name = m[0]
              case name
              when "quad"  then io << "    "
              when "qquad" then io << "        "
              when ",", ";", ":", " " then io << ' '
              else io << name
              end
              i += 1 + m[0].size
            elsif rest.size > 0
              io << rest[0]
              i += 2
            else
              i += 1
            end
          else
            io << c
            i += 1
          end
        end
      end
    end

    # Parse a raw string in math mode sharing macros/depth (for font cmds).
    private def sub_parse(str : String) : Array(Mml::Node)
      Parser.new(str, @display, @macros, @depth + 1).parse_list([:eof])
    end

    # ------------------------------------------------------------------
    # Style/color scopes for the rest of the current group

    private def style_rest(stop : Array(Symbol), displaystyle : String? = nil, scriptlevel : String? = nil) : Mml::Node
      was_small = @small_binom
      @small_binom = true if displaystyle == "false"
      node = wrap("mstyle", parse_list(stop))
      @small_binom = was_small
      node.set("displaystyle", displaystyle) if displaystyle
      node.set("scriptlevel", scriptlevel) if scriptlevel
      node
    end

    private def color_rest(stop : Array(Symbol)) : Mml::Node
      color = get_arg("color").not_nil!
      wrap("mstyle", parse_list(stop)).set("mathcolor", resolve_color(color))
    end

    private def make_textcolor : Mml::Node
      color = get_arg("textcolor").not_nil!
      wrap("mstyle", parse_arg_nodes("textcolor")).set("mathcolor", resolve_color(color))
    end

    # ------------------------------------------------------------------
    # color extension: \definecolor, \colorbox, \fcolorbox, color models

    private def handle_definecolor : Array(Mml::Node)
      name = get_arg("definecolor").not_nil!
      model = get_arg("definecolor").not_nil!
      spec = get_arg("definecolor").not_nil!
      @colors[name] = convert_color(model, spec)
      [] of Mml::Node
    end

    private def make_colorbox : Mml::Node
      color = get_arg("colorbox").not_nil!
      wrap("mstyle", parse_arg_nodes("colorbox")).set("mathbackground", resolve_color(color))
    end

    private def make_fcolorbox : Mml::Node
      frame = get_arg("fcolorbox").not_nil!
      bg = get_arg("fcolorbox").not_nil!
      inner = wrap("menclose", parse_arg_nodes("fcolorbox")).set("notation", "box")
      inner = wrap("mstyle", [inner]).set("mathcolor", resolve_color(frame))
      inner.set("mathbackground", resolve_color(bg))
    end

    private def resolve_color(color : String) : String
      return color if color.starts_with?('#')
      @colors[color]? || Symbols::COLORS[color]? || color
    end

    # Convert a \definecolor spec to a #rrggbb hex string.
    private def convert_color(model : String, spec : String) : String
      parts = spec.split(',').map(&.strip)
      num = ->(s : String) { s.to_f? || 0.0 }
      hex = ->(v : Float64) { ((v.clamp(0.0, 1.0) * 255).round.to_i).to_s(16).rjust(2, '0') }
      case model.downcase
      when "rgb"
        "##{hex.call(num.call(parts[0]? || "0"))}#{hex.call(num.call(parts[1]? || "0"))}#{hex.call(num.call(parts[2]? || "0"))}"
      when "rgb255", "RGB".downcase
        "##{hex.call((num.call(parts[0]? || "0")) / 255)}#{hex.call((num.call(parts[1]? || "0")) / 255)}#{hex.call((num.call(parts[2]? || "0")) / 255)}"
      when "gray"
        g = hex.call(num.call(parts[0]? || "0"))
        "##{g}#{g}#{g}"
      when "html"
        "##{spec.delete(' ')}"
      when "cmyk"
        c = num.call(parts[0]? || "0"); m = num.call(parts[1]? || "0")
        y = num.call(parts[2]? || "0"); k = num.call(parts[3]? || "0")
        "##{hex.call((1 - c - k).clamp(0.0, 1.0))}#{hex.call((1 - m - k).clamp(0.0, 1.0))}#{hex.call((1 - y - k).clamp(0.0, 1.0))}"
      else
        spec
      end
    end

    # ------------------------------------------------------------------
    # cancel extension: \cancel \bcancel \xcancel \sout

    private def make_cancel(notation : String) : Mml::Node
      wrap("menclose", parse_arg_nodes("cancel")).set("notation", notation)
    end

    # ------------------------------------------------------------------
    # physics extension (subset), seeded as predefined macros

    PHYSICS_MACROS = {
      "abs"     => Macro.new(1, "\\left| #1\\right|"),
      "norm"    => Macro.new(1, "\\left\\|#1\\right\\|"),
      "eval"    => Macro.new(1, "\\left.#1\\right|"),
      "order"   => Macro.new(1, "\\mathcal{O}\\left(#1\\right)"),
      "comm"    => Macro.new(2, "\\left[#1,#2\\right]"),
      "acomm"   => Macro.new(2, "\\left\\{#1,#2\\right\\}"),
      "pb"      => Macro.new(2, "\\left\\{#1,#2\\right\\}"),
      "bra"     => Macro.new(1, "\\left\\langle #1\\right|"),
      "ket"     => Macro.new(1, "\\left| #1\\right\\rangle"),
      "braket"  => Macro.new(1, "\\left\\langle #1\\right\\rangle"),
      "ketbra"  => Macro.new(2, "\\left| #1\\right\\rangle\\!\\left\\langle #2\\right|"),
      "dyad"    => Macro.new(2, "\\left| #1\\right\\rangle\\!\\left\\langle #2\\right|"),
      "mel"     => Macro.new(3, "\\left\\langle #1\\middle|#2\\middle|#3\\right\\rangle"),
      "matrixel" => Macro.new(3, "\\left\\langle #1\\middle|#2\\middle|#3\\right\\rangle"),
      "expval"  => Macro.new(1, "\\left\\langle #1\\right\\rangle"),
      "dd"      => Macro.new(0, "\\,\\mathrm{d}"),
      "dv"      => Macro.new(2, "\\frac{\\mathrm{d} #1}{\\mathrm{d}#2}"),
      "pdv"     => Macro.new(2, "\\frac{\\partial #1}{\\partial #2}"),
      "fdv"     => Macro.new(2, "\\frac{\\delta#1}{\\delta#2}"),
      "absval"  => Macro.new(1, "\\left| #1\\right|"),
    }

    # ------------------------------------------------------------------
    # Macros: \def and \newcommand

    private def handle_def(is_new : Bool) : Array(Mml::Node)
      if is_new
        name = get_arg("newcommand").not_nil!.lchop('\\')
        nargs = (get_brackets("0") || "0").to_i? || 0
      else
        skip_ws
        raise TexError.new("Missing control sequence after \\def") unless cur == '\\'
        @pos += 1
        name = read_cs
        nargs = 0
        # param text up to '{': count #<digit>
        while (c = cur) && c != '{'
          if c == '#'
            @pos += 1
            nargs += 1 if (d = cur) && d.number?
          end
          @pos += 1
        end
      end
      body = get_arg(is_new ? "newcommand" : "def").not_nil!
      @macros[name] = Macro.new(nargs, body)
      [] of Mml::Node
    end

    private def expand_macro(user_macro : Macro) : Nil
      @expansions += 1
      raise TexError.new("Macro expansion too deep (possible recursion)") if @expansions > MAX_EXPANSIONS
      args = Array.new(user_macro.nargs) { |i| get_arg("##{i + 1}") || "" }
      body = user_macro.body
      user_macro.nargs.step(by: -1, to: 1) do |i|
        body = body.gsub("##{i}", args[i - 1])
      end
      @string = body + @string[@pos..]
      @pos = 0
    end
  end
end
