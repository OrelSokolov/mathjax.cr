# Render every manifest formula with the v3-structure path renderer.
#
#   crystal run tools/render_ours.cr -- [out-dir]
#
require "../src/mathjax"

out_dir = ARGV[0]? || "/tmp/mj_v3/ours"
Dir.mkdir_p(out_dir)

manifest = File.read("dataset/manifest.json")
# minimal JSON walk: extract id/tex/display triples
cases = [] of {String, String, Bool}
manifest.scan(/"id":\s*"([^"]+)",\s*"title":[^}]*?"tex":\s*"((?:[^"\\]|\\.)*)",\s*"display":\s*(true|false)/m) do |m|
  tex = m[2].gsub("\\\\", "\\").gsub("\\\"", "\"")
  cases << {m[1], tex, m[3] == "true"}
end
abort "no cases parsed from manifest" if cases.empty?

ok = 0
cases.each do |id, tex, display|
  begin
    svg = MathJax.to_svg(tex, display: display, paths: true)
    File.write(File.join(out_dir, "#{id}.svg"), svg)
    ok += 1
  rescue ex
    STDERR.puts "FAIL #{id}: #{ex.message}"
  end
end
puts "rendered #{ok}/#{cases.size} -> #{out_dir}"
