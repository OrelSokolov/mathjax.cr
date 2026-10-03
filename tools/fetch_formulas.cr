# Fetch TeX formulas from English Wikipedia wikitext (<math>...</math> tags)
# via the MediaWiki API. Output: test/datasets/wikipedia.jsonl  {id, tex}
require "http/client"
require "json"
require "uri"

API = "https://en.wikipedia.org/w/api.php"
HEADERS = HTTP::Headers{"User-Agent" => "mathjax.cr-dataset-fetcher/0.1 (integration testing)"}

def api(params : Hash(String, String)) : JSON::Any
  query = URI::Params.encode(params)
  5.times do |attempt|
    sleep (2 ** attempt).seconds if attempt > 0
    response = HTTP::Client.get("#{API}?#{query}", HEADERS)
    case response.status_code
    when 200 then return JSON.parse(response.body)
    when 429
      retry_after = response.headers["Retry-After"]?.try(&.to_i?) || 3
      sleep retry_after.seconds
      next
    else
      raise "API error #{response.status_code}"
    end
  end
  raise "API rate limit exceeded"
end

# 1. Find articles containing <math> via CirrusSearch insource regex.
titles = [] of String
offset = nil
while titles.size < 700
  params = {
    "action"    => "query",
    "list"      => "search",
    "srsearch"  => "insource:/\\<math\\>/",
    "srlimit"   => "50",
    "srprop"    => "",
    "format"    => "json",
  }
  params["sroffset"] = offset.to_s if offset
  data = api(params)
  results = data.dig?("query", "search")
  break unless results
  batch = results.as_a.map { |r| r["title"].as_s }
  break if batch.empty?
  titles.concat(batch)
  cont = data.dig?("continue")
  break unless cont
  offset = cont["sroffset"]?.try(&.to_s)
  break unless offset
  sleep 50.milliseconds
end
titles.uniq!
puts "found #{titles.size} articles"

# 2. Fetch wikitext in batches of 20 and extract <math> formulas.
formulas = [] of String
seen = Set(String).new
titles.each_slice(20) do |slice|
  data = api({
    "action"  => "query",
    "prop"    => "revisions",
    "rvprop"  => "content",
    "rvslots" => "main",
    "titles"  => slice.join("|"),
    "format"  => "json",
    "formatversion" => "2",
  })
  pages = data.dig?("query", "pages").try(&.as_a?) || [] of JSON::Any
  pages.each do |page|
    content = page.dig?("revisions", 0, "slots", "main", "content").try(&.as_s?) || next
    content.scan(/<math([^>]*)>(.*?)<\/math>/m) do |m|
      tex = m[2].strip
      next if tex.empty?
      next if seen.includes?(tex)
      # Skip obvious non-TeX (chem markup etc.)
      next if m[1].includes?("chem")
      seen << tex
      formulas << tex
    end
  end
  sleep 300.milliseconds
end

puts "collected #{formulas.size} unique formulas"

# 3. Write dataset.
File.write("test/datasets/wikipedia.jsonl", formulas.first(1000).map_with_index { |tex, i|
  {id: i, tex: tex}.to_json
}.join("\n") + "\n")
puts "wrote #{Math.min(formulas.size, 1000)} formulas to test/datasets/wikipedia.jsonl"
