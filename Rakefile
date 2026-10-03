# Tasks for regenerating dataset artifacts.
#
#   rake generate:dataset:png            # oracle PNGs (default 2000px wide)
#   WIDTH=1000 rake generate:dataset:png # ...at a different width
#
# Renders every dataset/manifest.json formula with the original
# MathJax v3 (dataset/oracle/node_modules) and rasterizes each SVG with
# rsvg-convert. Requires: node, npm i (inside dataset/oracle), and
# rsvg-convert (on PATH or via RSVG_CONVERT=...).

dataset_root = File.join(__dir__, 'dataset')

desc 'Regenerate dataset/png/ — oracle PNGs from MathJax v3 + rsvg-convert'
task 'generate:dataset:png' do
  %w[
    dataset/oracle/node_modules/mathjax-full
  ].each do |dep|
    unless File.directory?(File.join(__dir__, dep))
      abort "missing #{dep} — run: cd dataset/oracle && npm install"
    end
  end

  rsvg = ENV['RSVG_CONVERT']
  unless rsvg
    rsvg = ENV['PATH'].split(File::PATH_SEPARATOR).lazy
                     .map { |d| File.join(d, 'rsvg-convert') }
                     .find { |f| File.executable?(f) }
  end
  unless rsvg && !rsvg.empty? && File.executable?(rsvg)
    abort 'rsvg-convert not found — install librsvg or set RSVG_CONVERT=/path/to/rsvg-convert'
  end
  ENV['RSVG_CONVERT'] = rsvg
  width = ENV.fetch('WIDTH', '2000')

  Dir.chdir(File.join(dataset_root, 'oracle')) do
    sh "node render_png.js #{width}"
  end
end
