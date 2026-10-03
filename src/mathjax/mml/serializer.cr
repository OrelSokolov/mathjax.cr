# Port of MathJax `core/MmlTree/SerializedMmlVisitor`: serialize the
# MML tree to a MathML string.
module MathJax::Mml
  module Serializer
    extend self

    def escape(text : String) : String
      text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
        .gsub('"', "&quot;")
    end

    def call(node : Node, indent : Int32? = nil) : String
      String.build do |io|
        write(io, node, indent, 0)
      end
    end

    private def write(io : IO, node : Node, indent : Int32?, depth : Int32) : Nil
      pad = indent ? ("  " * depth) : ""
      inner_pad = indent ? ("  " * (depth + 1)) : ""
      sep = indent ? "\n" : ""

      io << pad << "<" << node.kind
      node.attributes.each do |k, v|
        io << " " << k << "=\"" << escape(v) << "\""
      end

      if text = node.text
        io << ">" << escape(text) << "</" << node.kind << ">"
        io << sep if indent
      elsif node.children.empty?
        io << "/>"
        io << sep if indent
      else
        io << ">"
        io << sep if indent
        node.children.each do |child|
          write(io, child, indent, depth + 1)
        end
        io << inner_pad if indent
        io << "</" << node.kind << ">"
        io << sep if indent
      end
    end
  end
end
