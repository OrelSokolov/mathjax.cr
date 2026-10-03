# Port of MathJax `input/tex/base/BaseMappings.ts` and parts of the
# AMS mappings: control sequences -> MML leaf nodes.
module MathJax::TeX
  module Symbols
    # control sequence => {leaf kind, character}
    CHARS = {
      # Greek (lowercase)
      "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ",
      "epsilon" => "ϵ", "varepsilon" => "ε", "zeta" => "ζ", "eta" => "η",
      "theta" => "θ", "vartheta" => "ϑ", "iota" => "ι", "kappa" => "κ",
      "lambda" => "λ", "mu" => "μ", "nu" => "ν", "xi" => "ξ",
      "pi" => "π", "varpi" => "ϖ", "rho" => "ρ", "varrho" => "ϱ",
      "sigma" => "σ", "varsigma" => "ς", "tau" => "τ", "upsilon" => "υ",
      "phi" => "ϕ", "varphi" => "φ", "chi" => "χ", "psi" => "ψ",
      "omega" => "ω",
      # Greek (uppercase): operators (upright) per TeX convention
      "Gamma" => "Γ", "Delta" => "Δ", "Theta" => "Θ", "Lambda" => "Λ",
      "Xi" => "Ξ", "Pi" => "Π", "Sigma" => "Σ", "Upsilon" => "Υ",
      "Phi" => "Φ", "Psi" => "Ψ", "Omega" => "Ω",
      # Binary operators
      "times" => "×", "cdot" => "⋅", "div" => "÷", "pm" => "±", "mp" => "∓",
      "ast" => "∗", "star" => "⋆", "circ" => "∘", "bullet" => "•",
      "cup" => "∪", "cap" => "∩", "setminus" => "∖", "smallsetminus" => "∖",
      "wedge" => "∧", "vee" => "∨", "sqcap" => "⊓", "sqcup" => "⊔",
      "oplus" => "⊕", "ominus" => "⊖", "otimes" => "⊗", "oslash" => "⊘",
      "odot" => "⊙", "dagger" => "†", "ddagger" => "‡", "amalg" => "⨿",
      "uplus" => "⊎", "triangleleft" => "◃", "triangleright" => "▹",
      "wr" => "≀", "diamond" => "⋄", "bigtriangleup" => "△",
      "bigtriangledown" => "▽",
      # Relations
      "leq" => "≤", "geq" => "≥", "neq" => "≠", "equiv" => "≡",
      "sim" => "∼", "simeq" => "≃", "asymp" => "≍", "approx" => "≈",
      "cong" => "≅", "propto" => "∝", "prec" => "≺", "succ" => "≻",
      "preceq" => "⪯", "succeq" => "⪰", "ll" => "≪", "gg" => "≫",
      "doteq" => "≐", "models" => "⊨", "perp" => "⊥", "mid" => "∣",
      "parallel" => "∥", "nmid" => "∤", "in" => "∈", "notin" => "∉",
      "ni" => "∋", "subset" => "⊂", "supset" => "⊃",
      "subseteq" => "⊆", "supseteq" => "⊇",
      "subsetneq" => "⊊", "supsetneq" => "⊋",
      "sqsubset" => "⊏", "sqsupset" => "⊐",
      "sqsubseteq" => "⊑", "sqsupseteq" => "⊒",
      # Arrows
      "to" => "→", "rightarrow" => "→", "leftarrow" => "←", "gets" => "←",
      "leftrightarrow" => "↔", "Rightarrow" => "⇒", "impliedby" => "⇐",
      "Leftarrow" => "⇐", "Leftrightarrow" => "⇔", "iff" => "⟺",
      "implies" => "⟹", "mapsto" => "↦", "hookrightarrow" => "↪",
      "hookleftarrow" => "↩", "nearrow" => "↗", "searrow" => "↘",
      "nwarrow" => "↖", "swarrow" => "↙", "uparrow" => "↑",
      "downarrow" => "↓", "updownarrow" => "↕", "Uparrow" => "⇑",
      "Downarrow" => "⇓", "Updownarrow" => "⇕",
      "rightleftharpoons" => "⇌", "rightharpoonup" => "⇀",
      "rightharpoondown" => "⇁", "leftharpoonup" => "↼",
      "leftharpoondown" => "↽", "longmapsto" => "⟼",
      "longrightarrow" => "⟶", "longleftarrow" => "⟵",
      "longleftrightarrow" => "⟷", "Longrightarrow" => "⟹",
      "Longleftarrow" => "⟸", "Longleftrightarrow" => "⟺",
      # Big operators
      "sum" => "∑", "prod" => "∏", "coprod" => "∐",
      "int" => "∫", "iint" => "∬", "iiint" => "∭", "oint" => "∮",
      "bigcup" => "⋃", "bigcap" => "⋂", "bigoplus" => "⨁",
      "bigotimes" => "⨂", "bigodot" => "⨀", "biguplus" => "⨄",
      "bigsqcup" => "⨆", "bigvee" => "⋁", "bigwedge" => "⋀",
      # Logic / misc
      "forall" => "∀", "exists" => "∃", "nexists" => "∄", "neg" => "¬",
      "land" => "∧", "lor" => "∨", "therefore" => "∴", "because" => "∵",
      "emptyset" => "∅", "infty" => "∞", "partial" => "∂", "nabla" => "∇",
      "surd" => "√", "top" => "⊤", "bot" => "⊥", "vdash" => "⊢",
      "dashv" => "⊣", "angle" => "∠", "measuredangle" => "∡",
      "triangle" => "△", "square" => "□", "prime" => "′", "circ" => "∘",
      "degree" => "°", "hbar" => "ℏ", "ell" => "ℓ", "Re" => "ℜ",
      "Im" => "ℑ", "aleph" => "ℵ", "beth" => "ℶ", "gimel" => "ℷ",
      "daleth" => "ℸ", "wp" => "℘", "complement" => "∁",
      "cdots" => "⋯", "ldots" => "…", "vdots" => "⋮",
      "ddots" => "⋱", "mho" => "℧",
      # Negated relations
      "nleq" => "≰", "ngeq" => "≱", "nless" => "≮", "ngreater" => "≯",
      "nsubseteq" => "⊈", "nsupseteq" => "⊉", "napprox" => "≉",
      "nequiv" => "≢", "nprec" => "⊀", "nsucc" => "⊁", "nsim" => "≁",
      "ncong" => "≇", "not" => "̸",
      # Escaped literal characters
      "&" => "&", "%" => "%", "#" => "#", "_" => "_",
      # Delimiters usable as ordinary symbols
      "langle" => "⟨", "rangle" => "⟩", "lceil" => "⌈", "rceil" => "⌉",
      "lfloor" => "⌊", "rfloor" => "⌋", "vert" => "|", "Vert" => "∥",
      "lvert" => "|", "rvert" => "|", "lVert" => "∥", "rVert" => "∥",
      "lbrace" => "{", "rbrace" => "}", "lbrack" => "[", "rbrack" => "]",
      "backslash" => "\\",
      "{" => "{", "}" => "}", "|" => "∥",
      "ulcorner" => "⌜", "urcorner" => "⌝",
      "llcorner" => "⌞", "lrcorner" => "⌟",
    }

    # Which entries are identifiers (mi) rather than operators (mo).
    LETTERS = {
      "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta",
      "eta", "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu",
      "xi", "pi", "varpi", "rho", "varrho", "sigma", "varsigma", "tau",
      "upsilon", "phi", "varphi", "chi", "psi", "omega",
      "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon",
      "Phi", "Psi", "Omega", "hbar", "ell", "Re", "Im",
      "aleph", "beth", "gimel", "daleth", "wp", "complement",
      "infty", "partial", "nabla", "emptyset", "prime",
    }

    # Big operators: sub/sup become under/over in display mode.
    BIG_OPS = {
      "sum", "prod", "coprod", "bigcup", "bigcap", "bigoplus", "bigotimes",
      "bigodot", "biguplus", "bigsqcup", "bigvee", "bigwedge",
    }

    # Big operators whose limits always stay on the side (like \int).
    SIDEWAYS_BIG_OPS = {"int", "iint", "iiint", "oint"}

    # Identifier functions rendered upright; lim-style take limits below.
    # det/gcd/Pr are NamedOp in MathJax (mo, no function-application mark).
    LIM_FUNCS = {"lim", "limsup", "liminf", "max", "min", "sup", "inf",
                 "injlim", "projlim", "plim", "argmax", "argmin",
                 "det", "gcd", "Pr"}
    FUNCS = {"arccos", "arcsin", "arctan", "arg", "cos", "cosh", "cot",
             "coth", "csc", "deg", "dim", "exp", "hom", "ker",
             "lg", "ln", "log", "sec", "sin", "sinh", "tan", "tanh"}

    # \left / \right delimiter names => fence characters ("." = empty).
    DELIMITERS = {
      "(" => "(", ")" => ")", "[" => "[", "]" => "]", "|" => "|",
      "/" => "/", "." => "",
      "vert" => "|", "Vert" => "∥", "lvert" => "|", "rvert" => "|",
      "lVert" => "∥", "rVert" => "∥",
      "langle" => "⟨", "rangle" => "⟩", "lceil" => "⌈", "rceil" => "⌉",
      "lfloor" => "⌊", "rfloor" => "⌋", "lbrace" => "{", "rbrace" => "}",
      "lbrack" => "[", "rbrack" => "]",
      "backslash" => "\\", "langle" => "⟨",
      "ulcorner" => "⌜", "urcorner" => "⌝",
      "llcorner" => "⌞", "lrcorner" => "⌟",
    }

    # Simple aliases resolved before dispatch.
    ALIASES = {
      "ne" => "neq", "le" => "leq", "ge" => "geq",
      "lnot" => "neg", "varnothing" => "emptyset",
      "weierstrass" => "wp", "empty" => "∅",
      "to" => "rightarrow", "gets" => "leftarrow",
      "impliedby" => "Leftarrow", "iff" => "Longleftrightarrow",
      "implies" => "Longrightarrow",
    }

    # MathJax color extension palette (ColorConstants.ts)
    COLORS = {
      "Apricot" => "#FBB982",
      "Aquamarine" => "#00B5BE",
      "Bittersweet" => "#C04F17",
      "Black" => "#221E1F",
      "Blue" => "#2D2F92",
      "BlueGreen" => "#00B3B8",
      "BlueViolet" => "#473992",
      "BrickRed" => "#B6321C",
      "Brown" => "#792500",
      "BurntOrange" => "#F7921D",
      "CadetBlue" => "#74729A",
      "CarnationPink" => "#F282B4",
      "Cerulean" => "#00A2E3",
      "CornflowerBlue" => "#41B0E4",
      "Cyan" => "#00AEEF",
      "Dandelion" => "#FDBC42",
      "DarkOrchid" => "#A4538A",
      "Emerald" => "#00A99D",
      "ForestGreen" => "#009B55",
      "Fuchsia" => "#8C368C",
      "Goldenrod" => "#FFDF42",
      "Gray" => "#949698",
      "Green" => "#00A64F",
      "GreenYellow" => "#DFE674",
      "JungleGreen" => "#00A99A",
      "Lavender" => "#F49EC4",
      "LimeGreen" => "#8DC73E",
      "Magenta" => "#EC008C",
      "Mahogany" => "#A9341F",
      "Maroon" => "#AF3235",
      "Melon" => "#F89E7B",
      "MidnightBlue" => "#006795",
      "Mulberry" => "#A93C93",
      "NavyBlue" => "#006EB8",
      "OliveGreen" => "#3C8031",
      "Orange" => "#F58137",
      "OrangeRed" => "#ED135A",
      "Orchid" => "#AF72B0",
      "Peach" => "#F7965A",
      "Periwinkle" => "#7977B8",
      "PineGreen" => "#008B72",
      "Plum" => "#92268F",
      "ProcessBlue" => "#00B0F0",
      "Purple" => "#99479B",
      "RawSienna" => "#974006",
      "Red" => "#ED1B23",
      "RedOrange" => "#F26035",
      "RedViolet" => "#A1246B",
      "Rhodamine" => "#EF559F",
      "RoyalBlue" => "#0071BC",
      "RoyalPurple" => "#613F99",
      "RubineRed" => "#ED017D",
      "Salmon" => "#F69289",
      "SeaGreen" => "#3FBC9D",
      "Sepia" => "#671800",
      "SkyBlue" => "#46C5DD",
      "SpringGreen" => "#C6DC67",
      "Tan" => "#DA9D76",
      "TealBlue" => "#00AEB3",
      "Thistle" => "#D883B7",
      "Turquoise" => "#00B4CE",
      "Violet" => "#58429B",
      "VioletRed" => "#EF58A0",
      "White" => "#FFFFFF",
      "WildStrawberry" => "#EE2967",
      "Yellow" => "#FFF200",
      "YellowGreen" => "#98CC70",
      "YellowOrange" => "#FAA21A"
    }

    FONT_VARIANTS = {
      "mathrm" => "normal", "mathit" => "italic", "mathbf" => "bold",
      "mathsf" => "sans-serif", "mathtt" => "monospace",
      "mathbb" => "double-struck", "mathcal" => "script",
      "mathscr" => "script", "mathfrak" => "fraktur",
      "boldsymbol" => "bold", "bm" => "bold",
    }

    # Uppercase greek and letter-like operators MathJax renders upright.
    UPRIGHT = {"Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi",
               "Sigma", "Upsilon", "Phi", "Psi", "Omega",
               "infty", "nabla", "emptyset", "aleph"}

    # \not\<rel> merges into the negated character (ams \not handling).
    NOT_MERGE = {
      "in" => "∉", "=" => "≠", "<" => "≮", ">" => "≯",
      "leq" => "≰", "geq" => "≱", "less" => "≮", "gtr" => "≯",
      "subset" => "⊄", "supset" => "⊅", "subseteq" => "⊈",
      "supseteq" => "⊉", "equiv" => "≢", "approx" => "≉",
      "cong" => "≇", "sim" => "≁", "prec" => "⊀", "succ" => "⊁",
    }

    # Escaped literal characters (\& \% \# \_) become upright identifiers.
    ESCAPED_LITERALS = {"&", "%", "#", "_"}
  end
end
