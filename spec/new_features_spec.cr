require "./spec_helper"

describe "new backends and extensions" do
  describe "infix fractions" do
    it "parses \\over" do
      mml = MathJax.to_mathml("{a + b \\over c + d}")
      mml.should contain("<mfrac>")
      mml.should contain("<mi>a</mi><mo>+</mo><mi>b</mi>")
      mml.should contain("<mi>c</mi><mo>+</mo><mi>d</mi>")
    end

    it "parses \\atop with zero thickness" do
      MathJax.to_mathml("{a \\atop b}").should contain("linethickness=\"0\"")
    end

    it "parses \\choose with parens" do
      mml = MathJax.to_mathml("{n \\choose k}")
      mml.should contain("linethickness=\"0\"")
      mml.should contain("side=\"open\">(</mo>")
    end

    it "parses \\above with explicit thickness" do
      MathJax.to_mathml("{a \\above 1pt b}").should contain("mfrac")
    end
  end

  describe "\\genfrac" do
    it "builds a configurable fraction" do
      mml = MathJax.to_mathml("\\genfrac{[}{]}{0pt}{}{a}{b}")
      mml.should contain("linethickness=\"0pt\"")
      mml.should contain("side=\"open\">[</mo>")
    end

    it "empty delimiters give a bare fraction" do
      mml = MathJax.to_mathml("\\genfrac{}{}{}{}{a}{b}")
      mml.should contain("<mfrac")
      mml.should_not contain("fence")
    end
  end

  describe "\\middle" do
    it "works inside \\left...\\right" do
      mml = MathJax.to_mathml("\\left\\langle x \\middle| y \\right\\rangle")
      mml.should contain("stretchy=\"true\">|</mo>")
    end
  end

  describe "color extension" do
    it "converts rgb model to hex" do
      MathJax.to_mathml("\\definecolor{myred}{rgb}{1,0,0}\\textcolor{myred}{x}")
        .should contain("mathcolor=\"#ff0000\"")
    end

    it "converts gray model" do
      MathJax.to_mathml("\\definecolor{g}{gray}{0.5}\\textcolor{g}{x}")
        .should contain("#808080")
    end

    it "converts HTML model" do
      MathJax.to_mathml("\\definecolor{c}{HTML}{00FF00}\\textcolor{c}{x}")
        .should contain("#00FF00")
    end

    it "supports colorbox" do
      MathJax.to_mathml("\\colorbox{red}{x}").should contain("mathbackground=\"red\"")
    end

    it "supports fcolorbox" do
      mml = MathJax.to_mathml("\\fcolorbox{blue}{yellow}{x}")
      mml.should contain("mathcolor=\"blue\"")
      mml.should contain("mathbackground=\"yellow\"")
    end
  end

  describe "cancel extension" do
    it "maps to menclose notations" do
      MathJax.to_mathml("\\cancel{x}").should contain(%(notation="updiagonalstrike"))
      MathJax.to_mathml("\\bcancel{x}").should contain(%(notation="downdiagonalstrike"))
      MathJax.to_mathml("\\xcancel{x}").should contain(%(notation="updiagonalstrike downdiagonalstrike"))
      MathJax.to_mathml("\\sout{x}").should contain(%(notation="horizontalstrike"))
    end
  end

  describe "physics subset" do
    it "provides abs and norm" do
      MathJax.to_mathml("\\abs{-x}", physics: true).should contain(">|</mo>")
      MathJax.to_mathml("\\norm{v}", physics: true).should contain("∥")
    end

    it "provides derivatives" do
      mml = MathJax.to_mathml("\\dv{f}{x}", physics: true)
      mml.should contain("<mfrac>")
      mml.should contain("mathvariant=\"normal\"")
      MathJax.to_mathml("\\pdv{f}{x}", physics: true).should contain("∂")
    end

    it "provides dirac notation" do
      mml = MathJax.to_mathml("\\bra{a}\\ket{b}", physics: true)
      mml.should contain("⟨")
      mml.should contain("⟩")
      mml = MathJax.to_mathml("\\mel{a}{H}{b}", physics: true)
      mml.should contain("stretchy=\"true\">|</mo>")
    end

    it "is off by default" do
      expect_raises(MathJax::TeX::TexError, /Undefined control sequence/) do
        MathJax.to_mathml("\\abs{x}")
      end
    end
  end

  describe "MathML input" do
    it "parses MathML into the tree" do
      node = MathJax.from_mathml("<math><mfrac><mn>1</mn><mn>2</mn></mfrac></math>")
      node.children.first.kind.should eq("mfrac")
      node.children.first.children.map(&.text).should eq(["1", "2"])
    end

    it "preserves attributes and text" do
      node = MathJax.from_mathml(%(<math><mi mathvariant="normal">sin</mi></math>))
      node.children.first["mathvariant"].should eq("normal")
      node.children.first.text.should eq("sin")
    end

    it "handles namespaces" do
      node = MathJax.from_mathml(%(<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>))
      node.children.first.kind.should eq("mi")
    end

    it "round-trips through the serializer" do
      mml = MathJax.to_mathml("\\frac12")
      MathJax::Mml::Serializer.call(MathJax.from_mathml(mml)).should eq(mml)
    end

    it "raises without math element" do
      expect_raises(MathJax::Mml::MathmlError) do
        MathJax.from_mathml("<div>no math</div>")
      end
    end
  end

  describe "font metrics" do
    it "uses real TeX metrics" do
      MathJax::Fonts.width('a', "math_italic").should be_close(0.529, 0.01)
      MathJax::Fonts.width('0', "main").should be_close(0.5, 0.01)
      MathJax::Fonts.width('(', "size1").should be_close(0.458, 0.01)
    end
  end

  describe "SVG output" do
    it "emits svg with text at metric positions" do
      svg = MathJax.to_svg("x^2")
      svg.should start_with(%(<svg xmlns="http://www.w3.org/2000/svg"))
      svg.should contain("<text")
      svg.should contain("font-style=\"italic\"")
    end

    it "draws a fraction rule" do
      MathJax.to_svg("\\frac12").should contain("<line")
    end

    it "sizes the viewBox by measured content" do
      svg1 = MathJax.to_svg("x")
      svg2 = MathJax.to_svg("xxxx")
      w1 = svg1.match(/width="(\d+)"/).not_nil![1].to_i
      w2 = svg2.match(/width="(\d+)"/).not_nil![1].to_i
      w2.should be > w1
    end

    it "renders tables and radicals" do
      MathJax.to_svg("\\sqrt{x + \\begin{matrix} 1 \\end{matrix}}").should contain("<text")
    end
  end

  describe "AsciiMath input" do
    it "parses simple expressions" do
      mml = MathJax::Mml::Serializer.call(MathJax.parse_asciimath("x + 1"))
      mml.should contain("<mi>x</mi>")
      mml.should contain("<mn>1</mn>")
    end

    it "builds fractions from /" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("a/b"))
        .should contain("<mfrac>")
    end

    it "maps relations and arrows" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("x <= y")).should contain("≤")
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("x -> y")).should contain("→")
    end

    it "supports sub/sup" do
      mml = MathJax::Mml::Serializer.call(MathJax.parse_asciimath("x^2 + y_n"))
      mml.should contain("<msup>")
      mml.should contain("<msub>")
    end

    it "supports greek and sqrt" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("alpha + sqrt(2)"))
        .should contain("<mi>α</mi>")
    end

    it "puts limits under big operators" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("sum_(i=1)^n i"))
        .should contain("<munderover>")
    end

    it "parses matrices" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath("[[a,b],[c,d]]"))
        .should contain("<mtable>")
    end

    it "parses quoted text" do
      MathJax::Mml::Serializer.call(MathJax.parse_asciimath(%("hello" + x)))
        .should contain("<mtext>hello</mtext>")
    end
  end
end
