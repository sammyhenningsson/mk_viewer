# frozen_string_literal: true

module MkViewer
  module Keymap
    # legend/hold: what the key shows for a tap and a hold. shifted: extra text shown above
    # the legend, such as a key's adaptive rules. usage/mods: what a tap sends, when that's
    # known. hold_mods: the modifier mask this key sends when held. activates: the index of a
    # layer this key turns on while the layer below stays active (not `to`, which replaces it).
    Key = Struct.new(:legend, :hold, :shifted, :usage, :mods, :hold_mods, :transparent, :activates,
                     keyword_init: true) do
      def initialize(legend: nil, hold: nil, shifted: nil, usage: nil, mods: 0, hold_mods: 0, transparent: false,
                     activates: nil)
        super
      end

      def blank? = legend.to_s.empty? && hold.to_s.empty?
    end

    TRANSPARENT = Key.new(transparent: true).freeze

    Layer = Struct.new(:name, :keys)

    Map = Struct.new(:layers) do
      # The key that really acts at this position, looking through transparent
      # keys. Returns [key, inherited?].
      def resolve(layer, position)
        layer = layer.clamp(0, layers.size - 1)
        stack(layer).each do |index|
          key = layers[index].keys[position]
          return [key, index != layer] if key && !key.transparent
        end
        [TRANSPARENT, false]
      end

      # The layers probably active when this one is on top, highest first. Firmware
      # only reports the top layer, so the rest is inferred: below a layer is the
      # lowest layer with a key that activates it, or else the base layer.
      def stack(layer)
        (@stacks ||= {})[layer] ||= layer.zero? ? [0] : [layer, *stack(parent(layer))]
      end

      def layer_name(index) = layers[index]&.name || "Layer #{index}"

      def positions(layer) = layers[layer.clamp(0, layers.size - 1)].keys.each_index

      private

      def parent(layer)
        (0...layer).find { |index| layers[index].keys.any? { |key| key.activates == layer } } || 0
      end
    end
  end
end
