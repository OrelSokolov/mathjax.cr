# Shared normalization + diff/dump helpers for dataset comparison.
require "../src/mathjax"
require "json"

module Compare
  alias Node = MathJax::Mml::Node

  # Attributes that carry semantic meaning for our comparison.
  WHITELIST = {"mathvariant", "linethickness", "mathcolor", "mathbackground",
               "columnalign", "notation", "open", "close",
               "width", "minsize", "maxsize"}
  TOKEN_KINDS = {"mi", "mn", "mo", "mtext", "ms"}

  def self.normalize(node : Node) : Node
    # Flatten plain mrow/mstyle wrappers (inferred groups, scriptlevel=0).
    result = Node.new(node.kind)
    if TOKEN_KINDS.includes?(node.kind)
      result.text = node.text.to_s.strip
    end
    node.attributes.each do |k, v|
      next unless WHITELIST.includes?(k)
      if k == "width"
        v = ((v.to_f? || 0.0) * 1000).round.to_i.to_s
      end
      result.attributes[k] = v
    end
    node.children.each do |child|
      normalized = normalize(child)
      if normalized.kind.in?("mrow", "mstyle") && normalized.attributes.empty? && !normalized.text
        normalized.children.each { |gc| result.children << gc }
      else
        result.children << normalized
      end
    end
    result
  end

  # Returns nil when equal, else a human-readable first difference.
  def self.diff(a : Node, b : Node, path : String = "root") : String?
    return "#{path}: kind #{a.kind} != #{b.kind}" if a.kind != b.kind
    if TOKEN_KINDS.includes?(a.kind) || TOKEN_KINDS.includes?(b.kind)
      unless a.text == b.text
        return "#{path}: text #{a.text.inspect} != #{b.text.inspect}"
      end
    end
    if a.attributes != b.attributes
      return "#{path}: attrs #{a.attributes.inspect} != #{b.attributes.inspect}"
    end
    return "#{path}: child count #{a.children.size} != #{b.children.size}" if a.children.size != b.children.size
    a.children.zip(b.children).each_with_index do |(ca, cb), i|
      d = diff(ca, cb, "#{path}/#{ca.kind}[#{i}]")
      return d if d
    end
    nil
  end

  def self.dump(node : Node, depth : Int32) : Nil
    pad = "  " * depth
    if TOKEN_KINDS.includes?(node.kind)
      puts "#{pad}#{node.kind} #{node.text.inspect} #{node.attributes}"
    else
      puts "#{pad}#{node.kind} #{node.attributes}"
      node.children.each { |c| dump(c, depth + 1) }
    end
  end
end
