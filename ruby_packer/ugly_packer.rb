# -*- coding: utf-8 -*-

require 'ft2'
require 'fileutils'

if ARGV.length < 3
  abort("packing /path/to/font font_size output_dir" <<
        "Example: packing ~/.fonts/Roboto.ttf 16 ~/my/OpenGL/assets")
end

font_path = ARGV[0]
output_path = ARGV[2]

abort("Font #{ARGV[0]} not found") if !File.exists?(font_path)
abort("Expected a font file, got a #{File.ftype(font_path)} instead...") if !File.file?(font_path)
abort("The output path #{ARGV[2]} does not exist") if !File.exists?(output_path)
abort("#{ARGV[2]} is not a directory, it's a #{File.ftype(font_path)}") if !File.directory?(output_path)
  
face = FT2::Face.new font_path

puts "path:     #{font_path}",
     "glyphs:   #{face.glyphs}",
     "charmaps: #{face.num_charmaps}",
     "horiz:    #{face.horizontal?}",
     "vert:     #{face.vertical?}"

face.set_char_size(ARGV[1].to_i * 64, 0, 96, 0)

chars = "無 '\"0123456789@!?#%-_/\;:.,+=><$&|~`abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
extended = "éèêëîïôàùçµø«»äæáúûíóòßäâ‘’üîïôö©→↓ñ¿×÷¡ÁÆ¢ÊËÛÚÍÓÒÒŒØÄ„Â‚¥ÜÎÏÔÖÙ“”®←↑Ñ…∕−‑È™ÇÀ≠±^[]()=+*€$£￥"
jp_base = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをゐぁぇぃぉぅゃゅょっ゛゜アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲァェィォゥャュョッ"


def print_pixel(value)
  if    value == 255 then print "█"
  elsif value > 0xb0 then print "▓"
  elsif value > 0x80 then print "▒"
  elsif value > 0x40 then print "░"
  else                    print " "
  end
end

def invert_bitmap_in(result, bitmap)
  # puts "pitch : #{bitmap.pitch}"
  return if bitmap.width == 0
  bitmap.buffer.each_byte.each_slice(bitmap.pitch).to_a.reverse.each do |row| result << row end
end

Bearing = Struct.new(:x, :y)
Advance = Struct.new(:x, :y)
GlyphBitmap = Struct.new(:width, :pixels_per_row, :rows, :pixels, :bearing, :advance, :codepoint, :data)

module AlignHelpers
  def self.align_string_on(string, n_bytes_boundary)
    n_zeros_to_add = 
      n_bytes_boundary - (string.length % n_bytes_boundary)
    string << ("\0" * n_zeros_to_add)
    string
  end
end

class GL_GlyphData
  def initialize()
    @data = []
  end
  def add(tex_left:, tex_right:, tex_bottom:, tex_top:,
          offset_x_px:, offset_y_px:, 
          advance_x_px:, advance_y_px:, 
          width_px:, height_px:)
    puts "Advance X : #{advance_x_px}"
    @data << [tex_left, tex_right, tex_bottom, tex_top, 
              offset_x_px, offset_y_px, 
              advance_x_px, advance_y_px, 
              width_px, height_px]
  end
  
  def length
    return @data.length
  end
  alias :size :length
  
  @@pack_data = ->(data_array) { data_array.pack("S<10") }
  def to_binary
    @data.map(&@@pack_data).join("")
  end
  def infos_about(index)
    tex_left, tex_right, tex_bottom, tex_top,
    offset_x_px, offset_y_px, width_px, height_px = @data[index]
    "  Tex     : left: #{tex_left}, right: #{tex_right},\n"<<
    "            bottom: #{tex_bottom}, top: #{tex_top}\n" <<
    "  Offsets : x: #{offset_x_px} px, y: #{offset_y_px} px\n" <<
    "  Glyph   : width: #{width_px} px, height: #{height_px} px"
  end
end

class Codepoints
  def initialize()
    @data = []
  end
  def add(codepoint)
    @data << [codepoint]
  end
  def infos_about(index)
    codepoint = @data[index]
    "#{codepoint.pack("U*")} (#{codepoint.first}) :\n"
  end
  
  def length
    return @data.length
  end
  alias :size :length
  @@pack_data = ->(data_array) { data_array.pack("I<") }
  def to_binary
    bin_data = @data.map(&@@pack_data).join("")
  end
end

class ExportedContent
  
  @@header_size = 64
  @@hdr_fixed_elements_size = 32
  @@max_filename_length = @@header_size - @@hdr_fixed_elements_size
  
  @@errors = {
    filename_length_zero: "Empty filenames not allowed",
    filename_length_too_large: 
      "Filenames must weight less than #@@max_filename_length bytes",
    filename_not_defined:
      "The font filename must be defined first, using the :\n" <<
      "  ExportedContent#font_filename(filename)"
  }
  
  def initialize()
    @codepoints = Codepoints.new
    @glyphdata  = GL_GlyphData.new
  end
  
  def add_glyphdata(**data)
    @glyphdata.add(**data)
  end
  
  def add_codepoint(codepoint)
    @codepoints.add(codepoint)
  end
  
  def font_filename(filename)
    bytes_font_filename = filename.unpack("C*").pack("C*")
    bytes_length = bytes_font_filename.length
    if bytes_length > 0 && bytes_length < @@max_filename_length
      @font_filename = bytes_font_filename
      @font_filename_length = bytes_length
    else
      error_sym = :filename_length_too_large
      error_sym = :filename_length_zero if filename.length < 1
      raise ArgumentError, @@errors[error_sym]
    end
  end
  
  def to_s
    @codepoints.length.times do |i|
      puts(@codepoints.infos_about(i),
           @glyphdata.infos_about(i))
    end
  end
  
  def to_binary
    if @font_filename

      packed_codepoints = 
        AlignHelpers.align_string_on(@codepoints.to_binary, 16)
      packed_glyphdata  =
        AlignHelpers.align_string_on(@glyphdata.to_binary, 16)
      padded_filename = 
        AlignHelpers.align_string_on(@font_filename, 
                                     @@max_filename_length)

      codepoints_addr = 
        {start: @@header_size,
         stop: @@header_size + packed_codepoints.length}
      glyphdata_addr  = 
        {start: codepoints_addr[:stop],
         stop:  codepoints_addr[:stop] + packed_glyphdata.length}

      header = {
        n_codepoints:     @codepoints.length,
        codepoints_start: codepoints_addr[:start],
        glyphdata_start:  glyphdata_addr[:start],
        reserved: [0,0,0,0],
        font_filename_length: @font_filename_length,
        font_filename: @font_filename.bytes
      }
      packed_header = header.values.flatten!.pack("I8C*")

      "" << packed_header << packed_codepoints << packed_glyphdata
    end
  end
end

bitmaps = []

accumulated_height = 1
max_char_width = 0

current_glyph = face.glyph

(chars.codepoints | extended.codepoints).each do |codepoint|
  next unless face.load_char(codepoint, FT2::Load::RENDER)

  # p current_glyph.bitmap.buffer
  current_bitmap_data = []
  invert_bitmap_in(current_bitmap_data, current_glyph.bitmap)
  current_bitmap_data.flatten!
  bitmaps << GlyphBitmap.new(
    current_glyph.bitmap.width,
    current_glyph.bitmap.pitch,
    current_glyph.bitmap.rows,
    current_glyph.bitmap.pitch * current_glyph.bitmap.rows,
    Bearing.new(current_glyph.metrics.horiBearingX >> 6,
                current_glyph.metrics.horiBearingY >> 6),
    Advance.new(current_glyph.advance[0] >> 6,
                current_glyph.advance[1] >> 6),
    codepoint,
    current_bitmap_data
  )

  accumulated_height += current_glyph.bitmap.rows + 1
  max_char_width = max_char_width > current_glyph.bitmap.width ?
                   max_char_width : current_glyph.bitmap.width
end

bytes_per_pixels = 1
max_texture_height = 4096

char_width = max_char_width

texture_char_columns = 1 + (accumulated_height / max_texture_height)
texture_width = char_width * texture_char_columns
extra_padding = 1 + 1 * texture_char_columns
texture_width += extra_padding
texture_width += (32 - (texture_width % 32))

puts "accumulated_height: #{accumulated_height} columns : #{texture_char_columns}, column-width : #{texture_width}"


codepoints_dat = ExportedContent.new
super_bitmap = []

def sum_bitmaps_width(bitmap_group, bytes_per_pixels)
  bitmap_group.map(&:width).inject(0, &:+) * bytes_per_pixels
end

empty_line = Array.new(texture_width, 0)

super_bitmap << empty_line
current_height = 1

def uint16_norm(size, total_size)
  ((size / (total_size.to_f)) * 65535).to_i
end

accumulated_height = 4096

bitmaps.each_slice(texture_char_columns) do |bitmap_group|

  accumulated_width = 1
  bitmap_group.each {|bitmap|
    codepoints_dat.add_glyphdata(
      tex_left:   
        uint16_norm(accumulated_width, texture_width),
      tex_right:  
        uint16_norm(accumulated_width + bitmap.width, texture_width),
      tex_bottom: 
        uint16_norm(current_height, accumulated_height),
      tex_top: 
        uint16_norm(current_height + bitmap.rows, accumulated_height),
      offset_x_px: bitmap.bearing.x,
      offset_y_px: bitmap.bearing.y - bitmap.rows,
      advance_x_px: bitmap.advance.x,
      advance_y_px: bitmap.advance.y,
      width_px:    bitmap.width,
      height_px:   bitmap.rows
    )
    codepoints_dat.add_codepoint(bitmap.codepoint)
    accumulated_width += bitmap.width + 1
  }
  right_padding_size =
    texture_width - sum_bitmaps_width(bitmap_group, bytes_per_pixels) - extra_padding
  right_padding = Array.new(right_padding_size, 0)

  max_rows_in_group = bitmap_group.map(&:rows).max
  max_rows_in_group.times do |row|
    super_bitmap << 0
    bitmap_group.each do |bitmap|
      pixels_per_row = bitmap.pixels_per_row
      starting_point = row * pixels_per_row
      pixels = bitmap.data.slice(starting_point, pixels_per_row)
      if pixels.nil? || pixels.empty?
        pixels = Array.new(pixels_per_row, 0)
      end
      super_bitmap << pixels
      super_bitmap << 0
    end
    super_bitmap << right_padding
    current_height += 1
  end
  super_bitmap << empty_line
  current_height += 1
  p current_height
end

if current_height < 4096
  padding = Array.new(texture_width, 0)
  while current_height < 4096
    super_bitmap << padding
    current_height += 1
  end
end


super_bitmap.flatten!

super_bitmap.each_slice(texture_width) do |pixels|
  pixels.each {|pixel| print_pixel(pixel)}
  print "\n"
end

texture_height = super_bitmap.length / texture_width

module GL
  RED           = 0x1903
  ALPHA         = 0x1906
  UNSIGNED_BYTE = 0x1401
  TEXTURE_2D    = 0x0DE1
end

header =
  [texture_width, texture_height, GL::TEXTURE_2D, GL::ALPHA,
   GL::UNSIGNED_BYTE, 4]

p header
# p codepoints_dat.to_s

data_dir = File.join(output_path, "data")
data_file = File.join(data_dir, "codepoints.dat")
texture_dir = File.join(output_path, "textures")
texture_file = File.join(texture_dir, "super_bitmap.raw")

FileUtils.mkdir_p(data_dir)
FileUtils.mkdir_p(texture_dir)

File.write(texture_file, (header.pack("I<*") << super_bitmap.pack("C*")))
codepoints_dat.font_filename("super_bitmap.raw")
File.write(data_file, codepoints_dat.to_binary)
