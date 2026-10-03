# Integration test: run the dataset through mathjax.cr and compare the
# resulting MML trees against reference MathML produced by real MathJax
# (tools/make_reference.js) — same formulas, 1-to-1.
#
#   crystal run tools/compare.cr -- [dataset.jsonl] [--show N] [--diffs file]
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
    # Flatten plain mrows into their parent (inferred-group noise).
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
      # Flatten plain mrow/mstyle wrappers (inferred groups, scriptlevel=0).
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
end

show = 5
diffs_file = "test/datasets/diffs.txt"
dataset = "test/datasets/wikipedia_ref.jsonl"
args = ARGV.dup
if i = args.index("--show")
  show = args[i + 1].to_i
  args.delete_at(i, 2)
end
if i = args.index("--diffs")
  diffs_file = args[i + 1]
  args.delete_at(i, 2)
end
dataset = args[0] if args[0]?

total = 0
parsed = 0
equal = 0
our_errors = Hash(String, Int32).new(0)
diff_examples = [] of {Int32, String, String}
ref_available = 0

File.each_line(dataset) do |line|
  next if line.strip.empty?
  item = JSON.parse(line)
  tex = item["tex"].as_s
  total += 1
  ref_mml = item["mml_ref"]?.try(&.as_s?)
  ref_error = item["ref_error"]?.try(&.as_s?)

  if ref_error.nil? && ref_mml
    # MathJax's "noundefined" package turns unknown macros into merror
    # nodes — those are not real successes, exclude from comparison.
    ref_available += 1 unless ref_mml.includes?("merror")
  end

  ours =
    begin
      MathJax.parse(tex)
    rescue e : MathJax::TeX::TexError
      our_errors[e.message.to_s.split("\n").first] += 1
      next
    end
  parsed += 1

  next if ref_error || ref_mml.nil?
  next if ref_mml.includes?("merror") # undefined-macro fakes

  ref_node = MathJax.from_mathml(ref_mml)
  d = Compare.diff(Compare.normalize(ours), Compare.normalize(ref_node))
  if d.nil?
    equal += 1
  elsif diff_examples.size < 200
    diff_examples << {item["id"].as_i, tex, d}
  end
end

puts "=== mathjax.cr vs MathJax (#{dataset}) ==="
puts "total:        #{total}"
puts "we parsed:    #{parsed} (#{(parsed * 100.0 / total).round(1)}%)"
puts "comparable:   #{ref_available} (ref parsed, without noundefined fakes)"
puts "identical:    #{equal} (#{(equal * 100.0 / total).round(1)}% of total, #{(equal * 100.0 / [ref_available, 1].max).round(1)}% of comparable)"
puts ""
puts "top our errors:"
our_errors.to_a.sort_by { |(e, n)| -n }.first(12).each do |e, n|
  puts "  #{n.to_s.rjust(4)}  #{e}"
end

File.write(diffs_file, diff_examples.map { |id, tex, d|
  "## #{id}\ntex: #{tex}\ndiff: #{d}\n"
}.join("\n"))
puts ""
puts "first #{show} diffs (full list in #{diffs_file}):"
diff_examples.first(show).each do |id, tex, d|
  puts "[#{id}] #{tex[0, 70]}"
  puts "      #{d}"
end
