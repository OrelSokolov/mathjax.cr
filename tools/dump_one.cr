# Dump normalized trees (ours vs reference) for one dataset item.
#   crystal run tools/dump_one.cr -- 173
require "../src/mathjax"
require "./compare_norm"

id = ARGV[0].to_i
found = false
File.each_line("test/datasets/wikipedia_ref.jsonl") do |line|
  item = JSON.parse(line)
  next unless item["id"].as_i == id
  found = true
  tex = item["tex"].as_s
  puts "tex: #{tex}"
  ours = Compare.normalize(MathJax.parse(tex))
  ref = Compare.normalize(MathJax.from_mathml(item["mml_ref"].as_s))
  puts "\n--- ours ---"
  Compare.dump(ours, 0)
  puts "\n--- ref ---"
  Compare.dump(ref, 0)
  break
end
puts "id #{id} not found" unless found
