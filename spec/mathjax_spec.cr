require "./spec_helper"

describe MathJax do
  describe "atoms" do
    it "parses letters as mi" do
      MathJax.to_mathml("x").should contain("<mi>x</mi>")
    end

    it "parses numbers as mn (with decimals)" do
      MathJax.to_mathml("3.14").should contain("<mn>3.14</mn>")
      MathJax.to_mathml("12 34").should contain("<mn>12</mn>")
    end

    it "parses operators as mo" do
      MathJax.to_mathml("+").should contain("<mo>+</mo>")
      MathJax.to_mathml("=").should contain("<mo>=</mo>")
    end

    it "groups content in mrow" do
      MathJax.to_mathml("a+b").should contain("<mrow>")
    end

    it "wraps single-node expression without mrow" do
      MathJax.to_mathml("x").should_not contain("<mrow>")
    end

    it "ignores spaces and % comments" do
      MathJax.to_mathml("a  + % comment\n b").should contain("<mi>a</mi><mo>+</mo><mi>b</mi>")
    end
  end

  describe "scripts" do
    it "parses superscript" do
      MathJax.to_mathml("x^2").should contain("<msup><mi>x</mi><mn>2</mn></msup>")
    end

    it "parses subscript" do
      MathJax.to_mathml("a_i").should contain("<msub><mi>a</mi><mi>i</mi></msub>")
    end

    it "parses sub-superscript in any order" do
      MathJax.to_mathml("x_1^2").should contain("<msubsup>")
      MathJax.to_mathml("x^2_1").should contain("<msubsup>")
    end

    it "parses grouped script content" do
      MathJax.to_mathml("x^{n+1}").should contain("<msup><mi>x</mi><mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow></msup>")
    end

    it "converts primes to script" do
      MathJax.to_mathml("f'").should contain("<msup><mi>f</mi><mo>′</mo></msup>")
      MathJax.to_mathml("f''").should contain("<mo>″</mo>")
    end

    it "rejects double superscript" do
      expect_raises(MathJax::TeX::TexError, "Double superscript") do
        MathJax.to_mathml("x^2^3")
      end
    end
  end

  describe "fractions and roots" do
    it "parses frac" do
      mml = MathJax.to_mathml("\\frac{1}{2}")
      mml.should contain("<mfrac><mn>1</mn><mn>2</mn></mfrac>")
    end

    it "parses single-token frac arguments" do
      mml = MathJax.to_mathml("\\frac 1 2")
      mml.should contain("<mfrac><mn>1</mn><mn>2</mn></mfrac>")
    end

    it "parses sqrt and root" do
      MathJax.to_mathml("\\sqrt{x+1}").should contain("<msqrt>")
      MathJax.to_mathml("\\sqrt[3]{x}").should contain("<mroot>")
    end

    it "parses binom with zero thickness and big parens" do
      mml = MathJax.to_mathml("\\binom{n}{k}")
      mml.should contain("linethickness=\"0\"")
      mml.should contain(%q[<mo minsize="2.047em" maxsize="2.047em">(</mo>])
    end
  end

  describe "delimiters" do
    it "parses left-right with stretchy fences" do
      mml = MathJax.to_mathml("\\left(\\frac12\\right)")
      mml.should contain("stretchy=\"true\"")
      mml.should contain("<mo fence=\"true\" stretchy=\"true\" side=\"open\">(</mo>")
      mml.should contain("<mo fence=\"true\" stretchy=\"true\" side=\"close\">)</mo>")
    end

    it "supports named delimiters and empty" do
      mml = MathJax.to_mathml("\\left\\langle x \\right.")
      mml.should contain("<mo fence=\"true\" stretchy=\"true\" side=\"open\">⟨</mo>")
      mml.should_not contain("side=\"close\"")
    end
  end

  describe "symbols" do
    it "maps greek letters to mi" do
      MathJax.to_mathml("\\alpha").should contain("<mi>α</mi>")
    end

    it "maps operators to mo" do
      MathJax.to_mathml("\\times").should contain("<mo>×</mo>")
      MathJax.to_mathml("\\leq").should contain("<mo>≤</mo>")
      MathJax.to_mathml("\\to").should contain("<mo>→</mo>")
    end

    it "renders functions upright (multi-char mi, like MathJax)" do
      mml = MathJax.to_mathml("\\sin x")
      mml.should contain("<mi>sin</mi>")
      mml.should contain("<mo>\u2061</mo>")
    end

    it "raises on undefined control sequences" do
      expect_raises(MathJax::TeX::TexError, /Undefined control sequence/) do
        MathJax.to_mathml("\\nosuchcmd")
      end
    end
  end

  describe "big operators and limits" do
    it "keeps \\int limits to the side" do
      MathJax.to_mathml("\\int_0^1 x\\,dx").should contain("<msubsup>")
    end

    it "uses under/over for big ops even inline (movablelimits, as MathJax)" do
      MathJax.to_mathml("\\sum_{i=1}^n").should contain("<munderover>")
    end

    it "uses under/over in display mode" do
      MathJax.to_mathml("\\sum_{i=1}^n", display: true).should contain("<munderover>")
    end

    it "respects \\nolimits" do
      MathJax.to_mathml("\\sum\\nolimits_{i=1}", display: true).should contain("<msub>")
    end

    it "always puts lim-style limits below" do
      MathJax.to_mathml("\\lim_{x \\to 0}").should contain("<munder>")
    end
  end

  describe "text and fonts" do
    it "parses text mode" do
      # spaces become U+00A0, as in MathJax's nbsp text spaces
      MathJax.to_mathml("\\text{if } x").should contain("<mtext>if\u00A0</mtext>")
    end

    it "handles ~ and escapes in text" do
      MathJax.to_mathml("\\text{a~b}").should contain("<mtext>a\u00A0b</mtext>")
    end

    it "applies font variants" do
      MathJax.to_mathml("\\mathbf{v}").should contain("mathvariant=\"bold\"")
      MathJax.to_mathml("\\mathbb{R}").should contain("mathvariant=\"double-struck\"")
    end

    it "merges letter runs inside \\mathrm like MathJax" do
      mml = MathJax.to_mathml("\\mathrm{onions}")
      mml.should contain("<mi>onions</mi>")
      mml.should_not contain("mathvariant")
    end
  end

  describe "environments" do
    it "parses a matrix with rows and cells" do
      mml = MathJax.to_mathml("\\begin{matrix} a & b \\\\ c & d \\end{matrix}")
      # v3 arraydef spacing attributes (calibrated against the MathML oracle)
      mml.should contain("<mtable columnspacing=\"1em\" rowspacing=\"4pt\">")
      mml.should contain("<mtr>")
      mml.scan(/<mtd>/).size.should eq(4)
    end

    it "adds fences to pmatrix" do
      mml = MathJax.to_mathml("\\begin{pmatrix} 1 \\\\ 2 \\end{pmatrix}")
      mml.should contain("side=\"open\">(</mo>")
    end

    it "left-aligns cases (one column per cell, like MathJax)" do
      mml = MathJax.to_mathml("\\begin{cases} x & x>0 \\\\ 0 & \\text{else} \\end{cases}")
      mml.should contain("columnalign=\"left left\"")
      mml.should contain("<mo fence=\"true\" stretchy=\"true\"></mo>")
    end

    it "parses array column spec" do
      mml = MathJax.to_mathml("\\begin{array}{lr} a & b \\end{array}")
      mml.should contain("columnalign=\"left right\"")
    end

    it "rejects mismatched \\end" do
      expect_raises(MathJax::TeX::TexError, /Mismatched/) do
        MathJax.to_mathml("\\begin{matrix} a \\end{pmatrix}")
      end
    end
  end

  describe "macros" do
    it "supports \\def without arguments" do
      MathJax.to_mathml("\\def\\RR{\\mathbb{R}} \\RR").should contain("double-struck")
    end

    it "supports \\newcommand with arguments" do
      mml = MathJax.to_mathml("\\newcommand{\\sq}[1]{#1^2} \\sq{x}")
      mml.should contain("<msup><mi>x</mi><mn>2</mn></msup>")
    end

    it "expands macros recursively" do
      mml = MathJax.to_mathml("\\def\\a{1} \\def\\b{\\a+\\a} \\b")
      mml.should contain("<mn>1</mn><mo>+</mo><mn>1</mn>")
    end

    it "guards against infinite macro recursion" do
      expect_raises(MathJax::TeX::TexError, /expansion too deep/) do
        MathJax.to_mathml("\\def\\x{\\x} \\x")
      end
    end
  end

  describe "styles and spacing" do
    it "emits mspace for spacing commands" do
      MathJax.to_mathml("a\\,b").should contain("width=\"0.167em\"")
      MathJax.to_mathml("a\\!b").should contain("width=\"-0.167em\"")
    end

    it "wraps rest of group in mstyle" do
      mml = MathJax.to_mathml("{\\color{red} x + y}")
      mml.should contain("mathcolor=\"red\"")
      mml.should contain("<mi>x</mi><mo>+</mo><mi>y</mi>")
    end
  end

  describe "errors" do
    it "parse_or_error returns merror" do
      node = MathJax.parse_or_error("\\nosuch")
      node.children.first.kind.should eq("merror")
    end
  end

  describe "html output" do
    it "produces mjx spans" do
      html = MathJax.to_html("\\frac{1}{2}")
      html.should contain("class=\"mjx-cr\"")
      html.should contain("mjx-mfrac")
    end

    it "escapes html entities" do
      MathJax.to_html("\\text{a<b}").should contain("&lt;")
    end

    it "provides css" do
      MathJax.css.should contain(".mjx-mfrac")
    end
  end
end
