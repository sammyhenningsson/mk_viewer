# frozen_string_literal: true

require "yaml"

module MkViewer
  module Keymap
    # Reads the parts of a ZMK .keymap that a viewer needs. This isn't a devicetree
    # compiler: it handles #defines, behavior declarations and the keymap node.
    class Zmk
      BINDING_START = /&?\w+(?:\((?:[^()]|\([^()]*\))*\))?/

      # Optional labels: a keymap-drawer config, whose raw_binding_map is reused
      # so legends match the rendered layer images.
      def self.load(path, labels: nil)
        new(File.read(path), labels: labels && File.exist?(labels) ? File.read(labels) : nil).map
      end

      # Key positions [x, y] for a keyboard with no layout file, from how the first
      # layer's bindings are arranged in the file. It can't know the real stagger.
      def self.geometry(path) = new(File.read(path)).geometry

      def initialize(source, labels: nil)
        @text = strip_comments(source)
        @defines = {}
        @macros = {}
        read_defines
        @behaviors = read_behaviors
        @labels = labels ? (YAML.safe_load(labels).dig("parse_config", "raw_binding_map") || {}) : {}
      end

      def map
        raw = read_layers
        @layer_names = raw.map(&:first)
        Map.new(raw.map { |name, bindings| Layer.new(name, tokenize(bindings).map { |b| build(b) }) })
      end

      def geometry
        bindings = read_layers.first&.last or raise Error, "no layers found"
        rows = bindings.lines.map { |line| binding_offsets(line) }.reject(&:empty?)
        return grid(tokenize(bindings).size) unless rows.sum(&:size) == tokenize(bindings).size

        reference = rows.max_by(&:size)
        columns = column_positions(reference)
        rows.each_with_index.flat_map do |offsets, y|
          previous = -1
          offsets.each_with_index.map do |offset, index|
            room = reference.size - (offsets.size - index)
            previous = ((previous + 1)..room).min_by { |column| (reference[column] - offset).abs }
            [columns[previous], y.to_f]
          end
        end
      end

      private

      # Where each binding starts on a line.
      def binding_offsets(line)
        text = line.gsub("\t", "    ")
        offsets = []
        text.scan(BINDING_START) { offsets << Regexp.last_match.begin(0) if binding_start?(Regexp.last_match[0]) }
        offsets
      end

      def binding_start?(word) = word.start_with?("&") || (word.include?("(") && @macros.key?(word[/\A\w+/]))

      # One key width apart, plus a gap where the text has an unusually wide one:
      # that's normally the space between the halves of a split keyboard.
      def column_positions(reference)
        gaps = reference.each_cons(2).map { |a, b| b - a }
        typical = gaps.sort[gaps.size / 2] || 1
        widest = gaps.max || 0
        split = widest > typical * 1.6 ? gaps.index(widest) : nil
        reference.each_index.map { |index| split && index > split ? index + 1.0 : index.to_f }
      end

      def grid(count)
        Array.new(count) { |index| [(index % 10).to_f, (index / 10).to_f] }
      end

      def strip_comments(source)
        source.gsub(%r{/\*.*?\*/}m, "").gsub(%r{//[^\n]*}, "").gsub(/\\\n/, " ")
      end

      def read_defines
        @text.scan(/^\s*#define\s+(\w+)(\(([^)]*)\))?[ \t]*([^\n]*)$/) do |name, is_macro, params, body|
          if is_macro
            @macros[name] = [params.split(",").map(&:strip), body.strip]
          else
            @defines[name] = body.strip
          end
        end
      end

      def expand(token)
        seen = 0
        previous = nil
        until token == previous || (seen += 1) > 16
          previous = token
          token = token.gsub(/\b[A-Za-z_]\w*\b/) { |word| @defines.fetch(word, word) }
        end
        token
      end

      # { "HML" => { kind: :hold_tap, hold: "kp", tap: "kp" }, "AS_E" => { kind: :adaptive, inner: "..." } }
      def read_behaviors
        behaviors = {}
        @text.scan(/(\w+):\s*\w+\s*\{/) do |(name)|
          body = block_after(Regexp.last_match.end(0))
          case body[/compatible\s*=\s*"([^"]+)"/, 1]
          when "zmk,behavior-hold-tap"
            hold, tap = body[/bindings\s*=\s*(.*?);/m, 1].to_s.scan(/&(\w+)/).flatten
            behaviors[name] = { kind: :hold_tap, hold: hold, tap: tap }
          when "zmk,behavior-adaptive-key"
            behaviors[name] = { kind: :adaptive, inner: body[/bindings\s*=\s*<([^>]*)>/, 1] }
          end
        end
        behaviors
      end

      def block_after(start)
        depth = 1
        index = start
        while depth.positive? && index < @text.size
          depth += { "{" => 1, "}" => -1 }.fetch(@text[index], 0)
          index += 1
        end
        @text[start...index]
      end

      def read_layers
        match = @text.match(/\bkeymap\s*\{/) or raise Error, "no keymap node found"
        block_after(match.end(0)).scan(/(\w+)\s*\{(.*?)\}/m).filter_map do |node, body|
          bindings = body[/\bbindings\s*=\s*<(.*?)>\s*;/m, 1] or next
          [body[/display-name\s*=\s*"([^"]+)"/, 1] || node, bindings]
        end
      end

      # Splits a bindings list into strings like "&HML LSHIFT R" or "CAP(J)".
      def tokenize(text)
        words = text.scan(BINDING_START)
        words.each_with_object([]) do |word, bindings|
          if binding_start?(word)
            bindings << word
          elsif bindings.empty?
            raise Error, "unexpected token #{word.inspect} in bindings"
          else
            bindings[-1] += " #{word}"
          end
        end
      end

      def build(binding)
        key = binding.start_with?("&") ? from_behavior(binding) : from_macro(binding)
        apply_label(key, @labels[binding])
      end

      def from_macro(binding)
        name, argument = binding.match(/\A(\w+)\((.*)\)\z/).captures
        params, body = @macros.fetch(name)
        build(body.gsub(/\b#{Regexp.escape(params.first)}\b/, argument))
      end

      def apply_label(key, label)
        case label
        when String then key.dup.tap { |k| k.legend = label; k.hold = nil }
        when Hash
          key.dup.tap do |k|
            k.legend = label["t"].to_s if label["t"]
            k.hold = Keycodes.label(label["h"].to_s) if label["h"]
          end
        else key
        end
      end

      def from_behavior(binding)
        name, *args = binding.delete_prefix("&").split(" ")
        behavior = @behaviors[name]
        return from_hold_tap(behavior, args) if behavior&.fetch(:kind) == :hold_tap
        return build(behavior[:inner].strip.gsub(/\s+/, " ")) if behavior&.fetch(:kind) == :adaptive

        case name
        when "trans" then TRANSPARENT
        when "none" then Key.new
        when "kp" then tap_key(args.first)
        when "mo" then Key.new(legend: layer_label(args.first))
        when "to" then Key.new(legend: "→ #{layer_label(args.first)}")
        when "tog" then Key.new(legend: "⇄ #{layer_label(args.first)}")
        when "sl" then Key.new(legend: "1× #{layer_label(args.first)}")
        when "lt" then tap_key(args[1]).tap { |k| k.hold = layer_label(args[0]) }
        when "mt" then with_hold(tap_key(args[1]), "kp", args[0])
        when "caps_word" then Key.new(legend: "CapsWord")
        when "bt" then Key.new(legend: args.map { |a| Keycodes.label(a) }.join(" "))
        when "msc", "mmv", "mkp" then Key.new(legend: Keycodes.label(args.first))
        else Key.new(legend: name)
        end
      end

      def from_hold_tap(behavior, args)
        tap = behavior[:tap] == "kp" ? tap_key(args[1]) : Key.new(legend: args[1].to_s)
        with_hold(tap, behavior[:hold], args[0])
      end

      def with_hold(key, behavior, argument)
        case behavior
        when "kp"
          code = Keycodes.parse(expand(argument))
          key.hold = param_label(argument)
          key.hold_mods = code.mods if code.usage.nil?
        when "mo" then key.hold = layer_label(argument)
        when "to" then key.hold = "→ #{layer_label(argument)}"
        else key.hold = behavior
        end
        key
      end

      def tap_key(argument)
        code = Keycodes.parse(expand(argument))
        return Key.new(legend: param_label(argument), hold_mods: code.mods) if code.usage.nil? && code.mods.positive?

        Key.new(legend: param_label(argument), usage: code.usage, mods: code.mods)
      end

      # A keycode's legend: the keymap-drawer label for its name if there is one
      # (so SE_AT shows "@", not "RA(N2)"), or else a label from the expanded code.
      def param_label(argument)
        label = @labels["&kp #{argument}"]
        return label if label.is_a?(String)
        return Keycodes.label(argument) if Keycodes::LABELS.key?(argument)

        Keycodes.label(expand(argument))
      end

      def layer_label(argument)
        index = Integer(expand(argument), exception: false)
        index ? @layer_names[index] || "Layer #{index}" : argument
      end
    end
  end
end
