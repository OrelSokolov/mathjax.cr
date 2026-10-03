# Golden SVG dataset tests: every expected file must be a pure, valid
# <svg> document (no mjx-container), and mathjax.cr must be able to render
# every input formula without errors.
require "./spec_helper"
require "xml"
require "json"

MANIFEST = "dataset/manifest.json"
EXPECTED = "dataset/expected"
INPUTS   = "dataset/inputs"

describe "golden SVG dataset" do
  manifest =
    if File.exists?(MANIFEST)
      JSON.parse(File.read(MANIFEST))["cases"].as_a
    else
      nil
    end

  next pending "dataset not present (see dataset/README.md)" unless manifest

  it "has 1000 cases with matching input and expected files" do
    manifest.size.should eq(1000)
    manifest.each do |c|
      id = c["id"].as_s
      File.exists?(File.join(INPUTS, "#{id}.tex")).should be_true
      File.exists?(File.join(EXPECTED, "#{id}.svg")).should be_true
    end
  end

  it "expected files are pure SVG without mjx-container wrappers" do
    Dir.glob(File.join(EXPECTED, "*.svg")).each do |path|
      src = File.read(path)
      src.should start_with("<svg ")
      src.should_not contain("mjx-container")
    end
  end

  it "expected files are valid XML with an <svg> root" do
    Dir.glob(File.join(EXPECTED, "*.svg")).each do |path|
      doc = XML.parse(File.read(path))
      root = doc.children.find(&.element?)
      root.should_not be_nil
      root.not_nil!.name.should eq("svg")
    end
  end

  it "mathjax.cr renders every input to valid SVG without errors" do
    rendered = 0
    manifest.each do |c|
      tex = File.read(File.join(INPUTS, "#{c["id"].as_s}.tex")).chomp
      svg = MathJax.to_svg(tex, c["display"]?.try(&.as_bool?) || false)
      svg.should start_with(%(<svg xmlns="http://www.w3.org/2000/svg"))
      XML.parse(svg) # must be well-formed
      rendered += 1
    end
    rendered.should eq(manifest.size)
  end
end
