# CLI: mathjax [options] [file]
#
#   --mml            output MathML (default)
#   --html           output HTML (spans + mjx-* classes)
#   --svg            output SVG
#   --css            print the CSS for HTML output and exit
#   --display        display mode (block)
#   --physics        enable the physics macro subset (TeX input)
#   --ascii          input is AsciiMath instead of TeX
require "./mathjax"

format = "mml"
display = false
physics = false
ascii = false
source = ARGV.reject do |arg|
  case arg
  when "--mml"     then format = "mml"; true
  when "--html"    then format = "html"; true
  when "--svg"     then format = "svg"; true
  when "--display" then display = true; true
  when "--physics" then physics = true; true
  when "--ascii"   then ascii = true; true
  when "--css"     then puts MathJax.css; exit 0
  else false
  end
end

input = if source.empty?
          STDIN.gets_to_end
        else
          File.read(source.first)
        end
input = input.chomp

begin
  node = if ascii
           MathJax.parse_asciimath(input, display)
         else
           MathJax.parse(input, display, physics: physics)
         end
  case format
  when "mml"  then puts MathJax::Mml::Serializer.call(node)
  when "html" then puts MathJax::Html::Renderer.call(node)
  when "svg"  then puts MathJax::Svg::Renderer.call(node, display)
  end
rescue e : MathJax::TeX::TexError | MathJax::AsciiMath::AsciiMathError
  STDERR.puts "mathjax: #{e.message}"
  exit 1
end
