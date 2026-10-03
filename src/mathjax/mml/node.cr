# Port of MathJax `core/MmlTree`: a lightweight MML node tree.
module MathJax::Mml
  class Node
    property kind : String
    property text : String?
    property attributes : Hash(String, String)
    property children : Array(Node)

    def initialize(@kind : String, @text : String? = nil,
                   @attributes : Hash(String, String) = {} of String => String)
      @children = [] of Node
    end

    def self.leaf(kind : String, text : String, **attrs)
      new(kind, text).tap { |n| attrs.each { |k, v| n.attributes[k.to_s] = v.to_s } }
    end

    def add(node : Node) : self
      @children << node
      self
    end

    def add_all(nodes : Array(Node)) : self
      nodes.each { |n| @children << n }
      self
    end

    def add(kind : String, text : String? = nil, **attrs) : Node
      child = Node.new(kind, text)
      attrs.each { |k, v| child.attributes[k.to_s] = v.to_s }
      @children << child
      child
    end

    def set(attr : String, value : String) : self
      @attributes[attr] = value
      self
    end

    def [](attr : String) : String?
      @attributes[attr]?
    end

    def []?(attr : String) : String?
      @attributes[attr]?
    end

    # Wrap children in an mrow unless there is exactly one child.
    def mrow_if_needed : Node
      if @children.size == 1
        @children.first
      else
        row = Node.new("mrow")
        row.children.concat(@children)
        row
      end
    end
  end
end
