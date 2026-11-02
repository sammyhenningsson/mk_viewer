# frozen_string_literal: true

require "cairo"
require "pango"

module MkViewer
  # Draws a Session::View on a Cairo context, independently of any window.
  class Renderer
    Palette = Struct.new(:background, :key, :border, :text, :muted, :accent, :on_accent, keyword_init: true)

    def self.hex(value) = value.scan(/../).map { |pair| pair.to_i(16) / 255.0 }

    DARK = Palette.new(background: hex("1c1d22"), key: hex("2c2e36"), border: hex("3d4049"), text: hex("f1f2f4"),
                       muted: hex("9a9eaa"), accent: hex("f2a33a"), on_accent: hex("1c1d22"))
    LIGHT = Palette.new(background: hex("f3f3f1"), key: hex("ffffff"), border: hex("d3d4d0"), text: hex("1f2024"),
                        muted: hex("6a6d76"), accent: hex("c76a00"), on_accent: hex("ffffff"))

    FONT = "Sans"
    MARGIN = 20
    HEADER = 68
    PILL_ROW = 28
    SHIFTED_MAX = 0.5 # the most of a key's height its shifted text may take, at the top
    SHIFTED_MAX_WITH_HOLD = 0.3 # the same, when the key also has a hold legend to fit

    def initialize(dark: true)
      @palette = dark ? DARK : LIGHT
    end

    def draw(cr, width, height, view, connected: [], problem: nil)
      paint(cr, @palette.background)
      cr.paint
      return draw_empty(cr, width, height, problem) unless view

      top = draw_header(cr, width, view, connected)
      draw_keys(cr, width, height, view, top + 6)
      return unless view.message

      paint(cr, @palette.muted)
      text(cr, view.message, MARGIN, height - 30, width - MARGIN * 2, 14, center: false)
    end

    private

    def draw_empty(cr, width, height, problem)
      paint(cr, @palette.muted)
      text(cr, "No configured keyboard connected", 0, height / 2.0 - 24, width, 18)
      text(cr, problem, MARGIN, height / 2.0 + 6, width - MARGIN * 2, 13) if problem
    end

    def draw_header(cr, width, view, connected)
      name = view.layer_names[view.layer] || "Layer #{view.layer}"
      paint(cr, @palette.text)
      text(cr, name, MARGIN, 12, width / 2.0, 22, center: false, bold: true)
      paint(cr, @palette.muted)
      others = connected.empty? ? "" : "  ·  also connected: #{connected.join(', ')}"
      text(cr, "#{view.title} (#{view.transport})#{others}", MARGIN, 44, width - MARGIN * 2, 12, center: false)
      draw_layer_strip(cr, width, view)
    end

    # All layers, wrapping onto more rows if needed, with the active one filled in.
    # Returns the y coordinate below the strip.
    def draw_layer_strip(cr, width, view)
      x = MARGIN
      y = HEADER
      view.layer_names.each_with_index do |name, index|
        active = index == view.layer
        layout = pango(cr, name, 12, active)
        pill = layout.pixel_size[0] + 18
        if x + pill > width - MARGIN && x > MARGIN
          x = MARGIN
          y += PILL_ROW
        end
        if active
          paint(cr, @palette.accent)
          rounded(cr, x, y, pill, PILL_ROW - 4, 6)
          cr.fill
          paint(cr, @palette.on_accent)
        else
          paint(cr, @palette.muted)
        end
        place(cr, layout, x + 9, y + (PILL_ROW - 4 - layout.pixel_size[1]) / 2.0)
        x += pill + 4
      end
      y + PILL_ROW
    end

    def draw_keys(cr, width, height, view, area_top)
      right = view.keys.map(&:x).max + 1
      bottom = view.keys.map(&:y).max + 1
      area_w = width - MARGIN * 2
      area_h = height - area_top - MARGIN - (view.message ? 26 : 0)
      unit = [area_w / right.to_f, area_h / bottom.to_f].min
      left = MARGIN + (area_w - unit * right) / 2.0
      top = area_top + (area_h - unit * bottom) / 2.0
      view.keys.each { |key| draw_key(cr, key, left + key.x * unit, top + key.y * unit, unit) }
    end

    def draw_key(cr, key, x, y, unit)
      gap = unit * 0.05
      size = unit - gap * 2
      x += gap
      y += gap
      blank = key.legend.empty? && key.hold.empty?

      rounded(cr, x, y, size, size, unit * 0.12)
      paint(cr, blank ? @palette.background : @palette.key)
      cr.fill_preserve
      paint(cr, @palette.border)
      cr.line_width = 1
      cr.stroke
      if key.heat.positive?
        rounded(cr, x, y, size, size, unit * 0.12)
        paint(cr, @palette.accent, key.heat)
        cr.fill
      end

      lit = key.heat > 0.5
      paint(cr, lit ? @palette.on_accent : key.inherited ? @palette.muted : @palette.text)
      room = size * (key.hold.empty? ? SHIFTED_MAX : SHIFTED_MAX_WITH_HOLD)
      shifted = key.shifted.empty? ? nil : wrapped(cr, key.shifted, size * 0.92, room, unit * 0.15)
      legend_top = shifted ? size * 0.05 + shifted.pixel_size[1] : 0.0
      legend_bottom = key.hold.empty? ? size : size * 0.68
      fit(cr, key.legend, x, y + legend_top, size, legend_bottom - legend_top, unit * 0.27, bold: !key.inherited)
      unless key.hold.empty?
        paint(cr, lit ? @palette.on_accent : @palette.muted)
        fit(cr, key.hold, x, y + size * 0.64, size, size * 0.3, unit * 0.13)
      end
      return unless shifted

      paint(cr, lit ? @palette.on_accent : @palette.accent)
      place(cr, shifted, x + size * 0.04, y + size * 0.05)
    end

    # A centered layout that wraps between words, shrunk until it fits the box.
    def wrapped(cr, string, width, height, size)
      layout = nil
      size.step(1, -0.5) do |candidate|
        layout = pango(cr, string, candidate, false)
        layout.width = width * Pango::SCALE
        layout.wrap = :word
        layout.alignment = :center
        text_w, text_h = layout.pixel_size
        break if text_w <= width && text_h <= height
      end
      layout
    end

    # Centers text in a box, shrinking it to fit the width.
    def fit(cr, string, x, y, width, height, size, bold: false)
      return if string.empty?

      layout = pango(cr, string, size, bold)
      text_w, = layout.pixel_size
      limit = width * 0.86
      layout = pango(cr, string, size * limit / text_w, bold) if text_w > limit
      text_w, text_h = layout.pixel_size
      place(cr, layout, x + (width - text_w) / 2.0, y + (height - text_h) / 2.0)
    end

    def text(cr, string, x, y, width, size, center: true, bold: false)
      layout = pango(cr, string, size, bold)
      layout.width = width * Pango::SCALE
      layout.ellipsize = :end
      layout.alignment = center ? :center : :left
      place(cr, layout, x, y)
    end

    def pango(cr, string, size, bold)
      layout = cr.create_pango_layout
      layout.font_description = Pango::FontDescription.new("#{FONT} #{'Bold ' if bold}#{[size, 1].max.round(1)}px")
      layout.text = string
      layout
    end

    def place(cr, layout, x, y)
      cr.move_to(x, y)
      cr.show_pango_layout(layout)
    end

    def paint(cr, color, alpha = 1.0) = cr.set_source_rgba(*color, alpha)

    def rounded(cr, x, y, width, height, radius)
      cr.new_sub_path
      cr.arc(x + width - radius, y + radius, radius, -Math::PI / 2, 0)
      cr.arc(x + width - radius, y + height - radius, radius, 0, Math::PI / 2)
      cr.arc(x + radius, y + height - radius, radius, Math::PI / 2, Math::PI)
      cr.arc(x + radius, y + radius, radius, Math::PI, 1.5 * Math::PI)
      cr.close_path
    end
  end
end
