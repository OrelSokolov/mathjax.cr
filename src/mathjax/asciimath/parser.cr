# Port (subset) of MathJax `input/asciimath`: AsciiMath -> MML tree.
# Supports: identifiers, numbers, fractions (a/b), sub/sup (^ _ primes),
# sqrt/root, greek names, big operators (sum/prod/int) with limits,
# relations and arrows (<= >= != -> => <=> ...), functions (sin, ...),
# accents (hat/bar/vec/ul(...)), abs |x|, groups (...), sets {...},
# matrices [[..],[..]] and quoted text "...".
require "../mml/node"
require "../tex/symbols"

module MathJax::AsciiMath
  class AsciiMathError < Exception
  end

  # TeX symbol tables reused for AsciiMath names (alpha, sum, ...).
  Symbols = ::MathJax::TeX::Symbols

  class Parser
    def initialize(@string : String, @display : Bool = false)
      @pos = 0
      @tokens = tokenize(@string).as(Array(Token))
      @i = 0
    end

    def self.parse(input : String, display : Bool = false) : Mml::Node
      parser = new(input, display)
      nodes = parser.parse_sequence(nil)
      math = Mml::Node.new("math")
      math.set("display", "block") if display
      math.set("xmlns", "http://www.w3.org/1998/Math/MathML")
      math.add(nodes.size == 1 ? nodes.first : Mml::Node.new("mrow").tap { |r| r.children.concat(nodes) })
    end

    # ------------------------------------------------------------------
    # Tokens

    alias TokenKind = Symbol # :ident :number :text :op
    record Token, kind : TokenKind, value : String

    MULTI_OPS = ["<=>", "<->", "<=", ">=", "!=", "->", "=>", "~~", "**", "//", "<<", ">>", "...", "++", "--", "-="]

    GREEK = ::MathJax::TeX::Symbols::CHARS.keys.select { |k| !k.empty? && k[0].ascii_lowercase? }.to_set

    FUNCS = {"sin", "cos", "tan", "csc", "sec", "cot", "sinh", "cosh", "tanh",
             "log", "ln", "lg", "exp", "det", "dim", "gcd", "hom", "ker",
             "sup", "inf", "max", "min", "lim", "arg", "deg", "arcsin",
             "arccos", "arctan"}

    BIG_OPS = {"sum", "prod", "int", "oint", "coprod", "bigcup", "bigcap"}

    ACCENTS = {"hat" => "^", "bar" => "ˉ", "vec" => "→", "dot" => "˙",
               "ddot" => "¨", "ul" => "_"}

    private def tokenize(input : String) : Array(Token)
      tokens = [] of Token
      i = 0
      while i < input.size
        c = input[i]
        if c.whitespace?
          i += 1
        elsif c == '"'
          j = input.index('"', i + 1) || raise AsciiMathError.new("Unterminated text string")
          tokens << Token.new(:text, input[(i + 1)...j])
          i = j + 1
        elsif c.ascii_letter?
          j = i
          while j < input.size && input[j].ascii_letter?
            j += 1
          end
          tokens << Token.new(:ident, input[i...j])
          i = j
        elsif c.number?
          j = i
          while j < input.size && (input[j].number? || (input[j] == '.' && j + 1 < input.size && input[j + 1].number?))
            j += 1
          end
          tokens << Token.new(:number, input[i...j])
          i = j
        else
          matched = MULTI_OPS.find { |op| input[i, op.size]? == op }
          if matched
            tokens << Token.new(:op, matched)
            i += matched.size
          else
            tokens << Token.new(:op, c.to_s)
            i += 1
          end
        end
      end
      tokens
    end

    # ------------------------------------------------------------------
    # Parsing

    private def peek : Token?
      @tokens[@i]?
    end

    private def next_token : Token?
      t = @tokens[@i]?
      @i += 1 if t
      t
    end

    # stop: a set of op values that terminate the sequence (not consumed).
    protected def parse_sequence(stop : Set(String?)? = nil) : Array(Mml::Node)
      nodes = [] of Mml::Node
      loop do
        t = peek
        break if t.nil?
        if t.kind == :op && stop.try(&.includes?(t.value))
          break
        end
        nodes << parse_term(stop)
      end
      nodes
    end

    # term: postfix atoms chained, with / building fractions.
    private def parse_term(stop : Set(String?)? = nil) : Mml::Node
      left = parse_postfix(stop)
      while (t = peek) && t.kind == :op && t.value == "/"
        next_token
        right = parse_postfix(stop)
        frac = Mml::Node.new("mfrac").add(left).add(right)
        left = frac
      end
      left
    end

    private def parse_postfix(stop : Set(String?)? = nil) : Mml::Node
      base = parse_primary(stop)
      loop do
        t = peek
        break unless t && t.kind == :op
        case t.value
        when "^"
          next_token
          sup = parse_primary(stop)
          base = Mml::Node.new("msup").add(base).add(sup)
        when "_"
          next_token
          sub = parse_primary(stop)
          under_over = big_op?(base)
          base = Mml::Node.new(under_over ? "munder" : "msub").add(base).add(sub)
        when "'"
          next_token
          primes = 0
          while (t2 = peek) && t2.kind == :op && t2.value == "'"
            next_token
            primes += 1
          end
          base = Mml::Node.new("msup").add(base).add(Mml::Node.leaf("mo", prime_text(primes + 1)))
        else break
        end
        # sub followed by sup combines into msubsup / munderover
        t = peek
        if t && t.kind == :op && t.value == "^" && base.kind.in?("msub", "munder")
          next_token
          sup = parse_primary(stop)
          base = Mml::Node.new(base.kind == "munder" ? "munderover" : "msubsup")
            .add(base.children[0]).add(base.children[1]).add(sup)
        end
      end
      base
    end

    private def big_op?(node : Mml::Node) : Bool
      # AsciiMath puts limits below/above big operators regardless of mode.
      return false unless node.kind == "mo"
      text = node.text
      ::MathJax::TeX::Symbols::BIG_OPS.any? { |k| ::MathJax::TeX::Symbols::CHARS[k]? == text } ||
        ::MathJax::TeX::Symbols::SIDEWAYS_BIG_OPS.any? { |k| ::MathJax::TeX::Symbols::CHARS[k]? == text }
    end

    private def prime_text(n : Int32) : String
      case n
      when 1 then "′"
      when 2 then "″"
      when 3 then "‴"
      else        "′" * n
      end
    end

    private def parse_primary(stop : Set(String?)? = nil) : Mml::Node
      t = next_token
      raise AsciiMathError.new("Unexpected end of input") unless t
      case t.kind
      when :text
        Mml::Node.leaf("mtext", t.value.gsub('~', ' '))
      when :number
        Mml::Node.leaf("mn", t.value)
      when :ident
        case t.value
        when "sqrt"
          arg = parse_group_or_atom("sqrt")
          Mml::Node.new("msqrt").add(arg)
        when "root"
          n = parse_paren_args("root")
          x = parse_paren_args("root")
          Mml::Node.new("mroot").add(x).add(n)
        when "text", "mbox"
          Mml::Node.leaf("mtext", arg_text)
        when "bb"
          Mml::Node.new("mstyle").set("mathvariant", "double-struck").add(parse_paren_args("bb"))
        when "hat", "bar", "vec", "dot", "ddot", "ul"
          arg = parse_paren_args(t.value)
          chr = ACCENTS[t.value]
          if t.value == "ul"
            Mml::Node.new("munder").add(arg).add(Mml::Node.leaf("mo", chr).set("stretchy", "true"))
          else
            Mml::Node.new("mover").add(arg).add(Mml::Node.leaf("mo", chr).set("accent", "true"))
          end
        when "floor", "ceil"
          arg = parse_paren_args(t.value)
          o, c = t.value == "floor" ? {"⌊", "⌋"} : {"⌈", "⌉"}
          Mml::Node.new("mrow")
            .add(Mml::Node.leaf("mo", o).set("fence", "true"))
            .add(arg)
            .add(Mml::Node.leaf("mo", c).set("fence", "true"))
        else
          if GREEK.includes?(t.value)
            Mml::Node.leaf(::MathJax::TeX::Symbols::LETTERS.includes?(t.value) ? "mi" : "mo", ::MathJax::TeX::Symbols::CHARS[t.value])
          elsif BIG_OPS.includes?(t.value)
            Mml::Node.leaf("mo", ::MathJax::TeX::Symbols::CHARS[t.value])
          elsif FUNCS.includes?(t.value)
            if t.value.in?("lim", "max", "min", "sup", "inf")
              Mml::Node.leaf("mo", t.value)
            else
              Mml::Node.leaf("mi", t.value).set("mathvariant", "normal")
            end
          elsif t.value.size == 1
            Mml::Node.leaf("mi", t.value)
          else
            # Multi-letter identifier: one mi per character.
            Mml::Node.new("mrow").tap do |r|
              t.value.each_char { |ch| r.add(Mml::Node.leaf("mi", ch.to_s)) }
            end
          end
        end
      when :op
        case t.value
        when "("
          inner = parse_sequence(Set{")"})
          next_token # ')'
          row = Mml::Node.new("mrow").tap { |r| r.children.concat(inner) }
          row
        when "{"
          inner = parse_sequence(Set{"}"})
          next_token # '}'
          Mml::Node.new("mrow").tap { |r| r.children.concat(inner) }
        when "|"
          inner = parse_sequence(Set{"|"})
          next_token # '|'
          Mml::Node.new("mrow")
            .add(Mml::Node.leaf("mo", "|").set("fence", "true"))
            .add(inner.size == 1 ? inner.first : Mml::Node.new("mrow").tap { |r| r.children.concat(inner) })
            .add(Mml::Node.leaf("mo", "|").set("fence", "true"))
        when "["
          # matrix [[...],[...]] or plain bracket group
          if peek_try_matrix
            parse_matrix
          else
            inner = parse_sequence(Set{"]"})
            next_token
            Mml::Node.new("mrow")
              .add(Mml::Node.leaf("mo", "[").set("fence", "true"))
              .add(inner.size == 1 ? inner.first : Mml::Node.new("mrow").tap { |r| r.children.concat(inner) })
              .add(Mml::Node.leaf("mo", "]").set("fence", "true"))
          end
        else
          op_node(t.value)
        end
      else
        raise AsciiMathError.new("Unexpected token #{t.value}")
      end
    end

    private def arg_text : String
      t = next_token
      t && t.kind == :text ? t.value : ""
    end

    private def parse_paren_args(name : String) : Mml::Node
      t = peek
      if t && t.kind == :op && t.value == "("
        next_token
        inner = parse_sequence(Set{")"})
        next_token
        inner.size == 1 ? inner.first : Mml::Node.new("mrow").tap { |r| r.children.concat(inner) }
      else
        parse_primary
      end
    end

    private def parse_group_or_atom(name : String) : Mml::Node
      parse_paren_args(name)
    end

    private def peek_try_matrix : Bool
      # We are in the "[" branch and the outer "[" is already consumed:
      # a matrix starts when the next token is another "[".
      t = @tokens[@i]?
      !!(t && t.kind == :op && t.value == "[")
    end

    private def parse_matrix : Mml::Node
      # The outer "[" is already consumed by parse_primary.
      table = Mml::Node.new("mtable")
      loop do
        t = peek
        break if t.nil?
        if t.kind == :op && t.value == "["
          next_token
          row = table.add("mtr")
          loop do
            cell_nodes = parse_sequence(Set{",", "]"})
            row.add("mtd").children.concat(cell_nodes)
            ct = peek
            break unless ct && ct.kind == :op
            break unless ct.value == ","
            next_token
          end
          rt = peek
          if rt && rt.kind == :op && rt.value == "]"
            next_token
          else
            raise AsciiMathError.new("Malformed matrix")
          end
          nt = peek
          if nt && nt.kind == :op && nt.value == ","
            next_token
          elsif nt && nt.kind == :op && nt.value == "]"
            next_token
            break
          else
            raise AsciiMathError.new("Malformed matrix")
          end
        else
          raise AsciiMathError.new("Malformed matrix")
        end
      end
      table
    end

    private def op_node(op : String) : Mml::Node
      char = case op
             when "<=" then "≤"
             when ">=" then "≥"
             when "!=" then "≠"
             when "->" then "→"
             when "=>" then "⇒"
             when "<->" then "↔"
             when "<=>" then "⇔"
             when "~~" then "≈"
             when "**" then "∗"
             when "//" then "/"
             when "<<" then "≪"
             when ">>" then "≫"
             when "..." then "…"
             when "++" then "+"
             when "--" then "−"
             when "-=" then "≡"
             when "*" then "⋅"
             when "-" then "−"
             when "~" then "∼"
             when "@" then "∘"
             else op
             end
      Mml::Node.leaf("mo", char)
    end
  end
end
