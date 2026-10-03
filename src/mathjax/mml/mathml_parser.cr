# Port of MathJax `input/mathml`: parse a MathML string into the MML tree.
require "xml"
require "./node"

module MathJax::Mml
  class MathmlError < Exception
  end

  module MathmlParser
    extend self

    # Known MathML leaf (token) elements — their content becomes node text.
    TOKENS = {"mi", "mn", "mo", "mtext", "ms", "mspace", "mpadded"}

    def call(mathml : String) : Node
      document = XML.parse(mathml)
      root = find_math(document)
      node = build(root)
      # xmlns is a namespace declaration, not a regular attribute; the
      # serializer emits it, so keep it for round-tripping.
      node.attributes["xmlns"] = "http://www.w3.org/1998/Math/MathML" unless node.attributes.has_key?("xmlns")
      node
    end

    private def find_math(document : XML::Node) : XML::Node
      document.children.each do |child|
        return child if child.element? && local_name(child) == "math"
      end
      raise MathmlError.new("No <math> element found")
    end

    private def local_name(node : XML::Node) : String
      name = node.name
      name = name.split(':').last if name.includes?(':')
      name
    end

    private def build(xml : XML::Node) : Node
      kind = local_name(xml)
      node = Node.new(kind)
      xml.attributes.each do |attr|
        key = attr.name
        key = key.split(':').last if key.includes?(':')
        node.attributes[key] = attr.content
      end
      text = xml.content.strip
      if TOKENS.includes?(kind) && !text.empty?
        node.text = text
      else
        xml.children.each do |child|
          node.children << build(child) if child.element?
        end
      end
      node
    end
  end
end
