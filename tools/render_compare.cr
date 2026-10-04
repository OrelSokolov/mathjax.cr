# Render comparison: nanosvg.cr (pure Crystal port) vs librsvg (full SVG 1.1,
# C) on the golden SVG dataset. For each input SVG:
#
#   1. flatten <use xlink:href="#id"> into inline <path d="..."> (nanosvg has
#      no <use> support; positions in the MathJax dataset come from parent
#      <g transform=...>, so inlining is exact),
#   2. rasterize with nanosvg and with librsvg at the same pixel size,
#   3. composite both onto white and diff pixel-by-pixel,
#   4. write a side-by-side PNG (nanosvg | librsvg) into test/render/.
#
#   crystal run tools/render_compare.cr -- [file.svg ...] [--width N] [--ours]
#
# With no arguments a few files from dataset/expected are used; --ours adds
# formulas rendered by MathJax.to_svg (those use <text>, which nanosvg cannot
# draw — a visible demonstration that SVG renderers are not interchangeable).

require "../src/mathjax"
require "nanosvg"
require "digest/crc32"
require "compress/zlib"

# --- Minimal librsvg/cairo bindings (no headers needed, only the .so) -------

@[Link("rsvg-2")]
lib LibRsvg
  type Handle = Void*

  struct RsvgRectangle
    x, y, width, height : Float64
  end

  fun handle_new_from_data = rsvg_handle_new_from_data(
    data : UInt8*, len : UInt32, error : Void*
  ) : Handle
  fun handle_render_document = rsvg_handle_render_document(
    handle : Handle, cr : LibCairo::Context, viewport : RsvgRectangle*, error : Void*
  ) : LibC::Int
end

@[Link("cairo")]
lib LibCairo
  ARGB32 = 0

  type Surface = Void*
  type Context = Void*

  fun image_surface_create = cairo_image_surface_create(
    format : LibC::Int, width : LibC::Int, height : LibC::Int
  ) : Surface
  fun image_surface_get_data = cairo_image_surface_get_data(s : Surface) : UInt8*
  fun image_surface_get_stride = cairo_image_surface_get_stride(s : Surface) : LibC::Int
  fun surface_flush = cairo_surface_flush(s : Surface)
  fun surface_destroy = cairo_surface_destroy(s : Surface)
  fun create = cairo_create(s : Surface) : Context
  fun destroy = cairo_destroy(c : Context)
end

# --- PNG writer (RGBA 8-bit), same as the nanosvg example -------------------

module PNG
  def self.chunk(type : String, data : Bytes) : Bytes
    body = IO::Memory.new
    body.write(type.to_slice)
    body.write(data)
    io = IO::Memory.new
    io.write_bytes(data.size.to_u32, IO::ByteFormat::BigEndian)
    io.write(type.to_slice)
    io.write(data)
    io.write_bytes(Digest::CRC32.checksum(body.to_slice), IO::ByteFormat::BigEndian)
    io.to_slice
  end

  def self.encode_rgba(pixels : Bytes, width : Int32, height : Int32) : Bytes
    io = IO::Memory.new
    io.write Bytes[137, 80, 78, 71, 13, 10, 26, 10]
    ihdr = IO::Memory.new
    ihdr.write_bytes(width.to_u32, IO::ByteFormat::BigEndian)
    ihdr.write_bytes(height.to_u32, IO::ByteFormat::BigEndian)
    ihdr.write Bytes[8u8, 6u8, 0u8, 0u8, 0u8]
    io.write chunk("IHDR", ihdr.to_slice)
    raw = IO::Memory.new
    height.times do |y|
      raw.write_byte(0u8)
      raw.write(pixels[y * width * 4, width * 4])
    end
    deflated = IO::Memory.new
    writer = Compress::Zlib::Writer.new(deflated, level: 6)
    writer.write(raw.to_slice)
    writer.close
    io.write chunk("IDAT", deflated.to_slice)
    io.write chunk("IEND", Bytes.empty)
    io.to_slice
  end
end

# --- SVG preprocessing -------------------------------------------------------

module Prep
  # Replace <use href/xlink:href="#id"> with a copy of the referenced path.
  # Optional x/y on the <use> become a translate() transform.
  def self.flatten_uses(svg : String) : String
    paths = {} of String => String
    svg.scan(/<path\b[^>]*>/) do |m|
      tag = m[0]
      id = tag[/\bid="([^"]+)"/, 1]?
      d = tag[/\bd="([^"]+)"/, 1]?
      paths[id] = d if id && d
    end
    svg.gsub(/<use\b[^>]*?\/?>(?:\s*<\/use>)?/) do |tag|
      ref = tag[/\b(?:xlink:)?href="#([^"]+)"/, 1]?
      next tag unless ref && paths[ref]?
      x = tag[/\bx="([-\d.]+)"/, 1]?
      y = tag[/\by="([-\d.]+)"/, 1]?
      tf = tag[/\btransform="([^"]+)"/, 1]?
      # <use> semantics: the element's own transform first, then translate(x,y).
      parts = [] of String
      parts << tf if tf
      parts << %(translate(#{x || "0"},#{y || "0"})) if x || y
      tfs = parts.empty? ? "" : %( transform="#{parts.join(" ")}")
      %(<path d="#{paths[ref]}"#{tfs}/>)
    end
  end

  # MathJax crops stretchy-glyph pieces with nested <svg x y width height
  # viewBox>, which nanosvg.cr does not support (it even overwrites the root
  # viewport with the nested one). Replace each nested svg with the equivalent
  # group transform; the implicit viewport clip is dropped (for MathJax's
  # vertical-bar pieces the un-cropped tail just overlaps a neighbouring
  # piece of the same bar). The root tag has no x= attr and is left alone.
  def self.flatten_nested_svg(svg : String) : String
    n = 0
    out = svg.gsub(/<svg\b[^>]*>/) do |tag|
      x = tag[/\bx="([-\d.]+)"/, 1]?
      vb = tag[/\bviewBox="([-\d.eE+ ]+)"/, 1]?
      w = tag[/\bwidth="([-\d.]+)"/, 1]?
      h = tag[/\bheight="([-\d.]+)"/, 1]?
      next tag unless x && vb && w && h
      a = vb.split.reject(&.empty?).map(&.to_f)
      next tag unless a.size == 4 && a[2] != 0 && a[3] != 0
      y = tag[/\by="([-\d.]+)"/, 1]? || "0"
      sx = w.to_f / a[2]
      sy = h.to_f / a[3]
      tx = x.to_f - a[0] * sx
      ty = y.to_f - a[1] * sy
      n += 1
      %(<g transform="translate(#{tx} #{ty}) scale(#{sx} #{sy})">)
    end
    # The first n "</svg>" are the nested closes (the root's is last).
    pos = 0
    n.times do
      i = out.index("</svg>", pos) || break
      out = "#{out[0, i]}</g>#{out[i + 6..]}"
      pos = i + 4
    end
    out
  end

  # nanosvg has no CSS currentColor; the default CSS color is black, so
  # resolving it by hand matches what librsvg does with the same input.
  def self.resolve_current_color(svg : String) : String
    svg.gsub("currentColor", "#000000")
  end

  # viewBox "minx miny w h" — the only reliable common size source: nanosvg
  # and librsvg disagree on resolving font-relative units (ex) in width/height.
  def self.view_box(svg : String) : {Float32, Float32, Float32, Float32}?
    vb = svg[/viewBox="([-\d.eE+ ]+)"/, 1]?
    return nil unless vb
    a = vb.split.reject(&.empty?).map(&.to_f32)
    return nil unless a.size == 4
    {a[0], a[1], a[2], a[3]}
  end
end

# --- Renderers ----------------------------------------------------------------

module Rsvg
  record Render, rgba : Bytes, w : Int32, h : Int32

  # Render with librsvg into an ARGB32 surface, return straight (non
  # premultiplied) RGBA.
  def self.render(svg : String, w : Int32, h : Int32) : Render
    data = svg.to_slice
    handle = LibRsvg.handle_new_from_data(data, data.size, Pointer(Void).null)
    raise "librsvg: failed to parse SVG" unless handle

    surface = LibCairo.image_surface_create(LibCairo::ARGB32, w, h)
    cr = LibCairo.create(surface)
    viewport = LibRsvg::RsvgRectangle.new(
      x: 0.0, y: 0.0, width: w.to_f64, height: h.to_f64)
    ok = LibRsvg.handle_render_document(handle, cr, pointerof(viewport),
      Pointer(Void).null)
    LibCairo.destroy(cr)
    raise "librsvg: render failed" unless ok != 0
    LibCairo.surface_flush(surface)

    stride = LibCairo.image_surface_get_stride(surface)
    raw = LibCairo.image_surface_get_data(surface)
    rgba = Bytes.new(w * h * 4)
    h.times do |y|
      row = Slice.new(raw + y * stride, w * 4)
      w.times do |x|
        b, g, r, a = row[x*4], row[x*4+1], row[x*4+2], row[x*4+3]
        if a == 255
          rgba[y*w*4 + x*4] = r; rgba[y*w*4 + x*4 + 1] = g
          rgba[y*w*4 + x*4 + 2] = b
        elsif a == 0
          # leave 0
        else
          rgba[y*w*4 + x*4] = Math.min(255, (r.to_u32 * 255 + a // 2) // a).to_u8
          rgba[y*w*4 + x*4 + 1] = Math.min(255, (g.to_u32 * 255 + a // 2) // a).to_u8
          rgba[y*w*4 + x*4 + 2] = Math.min(255, (b.to_u32 * 255 + a // 2) // a).to_u8
        end
        rgba[y*w*4 + x*4 + 3] = a
      end
    end
    LibCairo.surface_destroy(surface)
    Render.new(rgba, w, h)
  end
end

module Nano
  record Render, rgba : Bytes, w : Int32, h : Int32

  def self.render(svg : String, vb, w : Int32, h : Int32) : Render
    image = NanoSVG.parse(Prep.resolve_current_color(svg), "px", 96.0f32)
    # The port's scale_to_viewbox already maps the viewBox onto
    # image.width x image.height, so shapes are viewport-relative.
    scale = image.width > 0 ? w.to_f32 / image.width : 1.0f32
    rgba = NanoSVG::Rasterizer.rasterize(image, 0.0f32, 0.0f32, scale, w, h)
    Render.new(rgba, w, h)
  end
end

# --- Diff ----------------------------------------------------------------------

module Diff
  # Composite onto white → per-pixel max channel delta.
  record Result, mean : Float64, pct_bad : Float64, max : Int32

  def self.run(a : Bytes, b : Bytes, w : Int32, h : Int32, threshold = 16) : Result
    total = 0_i64
    bad = 0_i64
    max = 0
    h.times do |y|
      w.times do |x|
        i = (y * w + x) * 4
        delta = 0
        3.times do |c|
          ca = (a[i + c].to_u32 * a[i+3].to_u32 + (255_u32 - a[i+3]) * 255 + 127) // 255
          cb = (b[i + c].to_u32 * b[i+3].to_u32 + (255_u32 - b[i+3]) * 255 + 127) // 255
          delta = {delta, (ca.to_i32 - cb.to_i32).abs}.max
        end
        total += delta
        bad += 1 if delta > threshold
        max = {max, delta}.max.to_i32
      end
    end
    n = (w * h).to_f64
    Result.new(total / n, bad / n * 100.0, max)
  end
end

# --- Side-by-side image ---------------------------------------------------------

def side_by_side(a : Bytes, b : Bytes, w : Int32, h : Int32) : Bytes
  sep = 4
  total_w = w * 2 + sep
  img = Bytes.new(total_w * h * 4, 255_u8) # opaque white
  put = ->(buf : Bytes, dst_x : Int32) do
    h.times do |y|
      w.times do |x|
        o = (y * total_w + dst_x + x) * 4
        s = (y * w + x) * 3
        3.times { |c| img[o + c] = buf[s + c] }
      end
    end
  end
  put.call(a, 0)
  put.call(b, w + sep)
  PNG.encode_rgba(img, total_w, h)
end

def composite_on_white(rgba : Bytes, w : Int32, h : Int32) : Bytes
  rgb = Bytes.new(w * h * 3)
  h.times do |y|
    w.times do |x|
      i = (y * w + x) * 4
      o = (y * w + x) * 3
      a = rgba[i + 3]
      3.times do |c|
        rgb[o + c] = ((rgba[i + c].to_u32 * a + (255 - a) * 255 + 127) // 255).to_u8
      end
    end
  end
  rgb
end

# --- Main -----------------------------------------------------------------------

module Main
  extend self

  class_property batch = false
  class_property results = [] of {String, Float64, Float64}

  def run(svg : String, name : String, width : Int32, outdir : String) : Nil
    vb = Prep.view_box(svg) || {0.0f32, 0.0f32, 400.0f32, 100.0f32}
    w = width
    h = {(vb[3] * width / vb[2]).round.to_i32, 1}.max

    rsvg = Rsvg.render(svg, w, h)
    flat = Prep.flatten_nested_svg(Prep.flatten_uses(svg))
    nano = Nano.render(flat, vb, w, h)

    res = Diff.run(nano.rgba, rsvg.rgba, w, h)
    printf "%-28s %dx%-4d mean=%6.2f  bad(>16)=%5.1f%%  max=%3d\n",
      name, w, h, res.mean, res.pct_bad, res.max
    Main.results << {name, res.mean, res.pct_bad}
    return if Main.batch

    a = composite_on_white(nano.rgba, w, h)
    b = composite_on_white(rsvg.rgba, w, h)
    png = side_by_side(a, b, w, h)
    File.write(File.join(outdir, "#{name}.side.png"), png)
  end
end

width = 480
ours = false
files = [] of String
ARGV.each do |arg|
  case arg
  when /^--width=(\d+)$/ then width = $1.to_i
  when "--ours"          then ours = true
  when "--batch"         then Main.batch = true
  else files << arg
  end
end

if files.empty?
  files = Dir["dataset/expected/*.svg"].first(5).map do |path|
    File.basename(path, ".svg")
  end
end

outdir = "test/render"
Dir.mkdir_p(outdir)

total = 0
files.each do |name|
  path = name.ends_with?(".svg") ? name : "dataset/expected/#{name}.svg"
  svg = File.read(path)
  Main.run(svg, File.basename(path, ".svg"), width, outdir)
  total += 1
end

if ours
  {"quadratic" => "\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}",
   "sum" => "\\sum_{i=1}^n i^2"}.each do |name, tex|
    svg = MathJax.to_svg(tex)
    File.write("#{outdir}/#{name}.ours.svg", svg)
    Main.run(svg, "#{name}.ours", width, outdir)
    total += 1
  end
end

puts "\nside-by-side images (nanosvg | librsvg): #{outdir}/" unless Main.batch
puts "total: #{total}"

if Main.batch
  rs = Main.results
  buckets = {"<1 (AA noise)" => 0, "1..3" => 0, "3..8" => 0, ">8" => 0}
  rs.each do |_, mean, _|
    case mean
    when ...1 then buckets["<1 (AA noise)"] += 1
    when ...3 then buckets["1..3"] += 1
    when ...8 then buckets["3..8"] += 1
    else           buckets[">8"] += 1
    end
  end
  puts "\nmean per-pixel diff distribution (0..255 scale):"
  buckets.each { |k, v| printf "  %-14s %4d  (%4.1f%%)\n", k, v, v * 100.0 / rs.size }
  puts "worst 10:"
  rs.sort_by { |_, mean, _| -mean }.first(10).each do |name, mean, pct|
    printf "  %-28s mean=%6.2f bad=%5.1f%%\n", name, mean, pct
  end
  puts "median mean diff: #{rs.map { |_, m, _| m }.sort[rs.size // 2]}"
end
