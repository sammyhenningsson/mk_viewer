# frozen_string_literal: true

module MkViewer
  module Keymap
    # legend/hold: what the key shows for a tap and a hold. usage/mods: what a tap sends, when that's known.
    # hold_mods: the modifier mask this key sends when held.
    Key = Struct.new(:legend, :hold, :usage, :mods, :hold_mods, :transparent, keyword_init: true) do
      def initialize(legend: nil, hold: nil, usage: nil, mods: 0, hold_mods: 0, transparent: false)
        super
      end

      def blank? = legend.to_s.empty? && hold.to_s.empty?
    end

    TRANSPARENT = Key.new(transparent: true).freeze

    Layer = Struct.new(:name, :keys)

    Map = Struct.new(:layers) do
      # The key that really acts at this position, looking through transparent
      # keys. Returns [key, inherited?]. Firmware only reports the highest active
      # layer, so lower layers are an approximation of the actual layer stack.
      def resolve(layer, position)
        layer = layer.clamp(0, layers.size - 1)
        layer.downto(0) do |index|
          key = layers[index].keys[position]
          return [key, index != layer] if key && !key.transparent
        end
        [TRANSPARENT, false]
      end

      def layer_name(index) = layers[index]&.name || "Layer #{index}"

      def positions(layer) = layers[layer.clamp(0, layers.size - 1)].keys.each_index
    end
  end
end
