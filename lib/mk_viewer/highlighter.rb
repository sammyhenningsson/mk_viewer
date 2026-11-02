# frozen_string_literal: true

require "set"

module MkViewer
  # Works out which keys are down when firmware only reports the HID keycodes it
  # sends rather than physical positions. A key stays where it was first found
  # until released, even if the layer changes while it's held.
  class Highlighter
    def initialize(keymap)
      @keymap = keymap
      @keys = {}
      @mods = {}
    end

    def update(layer, usages, mods)
      @keys.select! { |usage, _| usages.include?(usage) }
      usages.each do |usage|
        # A key not found yet may match on a later report, with its modifiers.
        @keys[usage] = find_key(layer, usage, mods) if @keys[usage].nil? || @keys[usage][:positions].empty?
      end

      # Modifiers implied by a key, like the Shift in LS(N8), aren't a held mod.
      implied = @keys.values.sum(0) { |found| found[:mods] }
      remaining = mods & ~implied
      @mods.select! { |mask, _| remaining & mask == mask }
      @mods.each_key { |mask| remaining &= ~mask }
      mod_keys(layer).each do |mask, positions|
        next unless remaining & mask == mask

        @mods[mask] = positions
        remaining &= ~mask
      end

      (@keys.values.flat_map { |found| found[:positions] } + @mods.values.flatten).to_set
    end

    private

    def find_key(layer, usage, mods)
      [layer, 0].uniq.each do |index|
        matches = candidates(index) { |key| key.usage == usage && (key.mods & ~mods).zero? }
        next if matches.empty?

        best = matches.map { |_, key| key.mods }.max_by { |mask| mask.digits(2).sum }
        return { positions: matches.select { |_, key| key.mods == best }.map(&:first), mods: best }
      end
      { positions: [], mods: 0 }
    end

    # Modifier keys on the layer, with combined ones like Meh checked first.
    def mod_keys(layer)
      found = Hash.new { |hash, mask| hash[mask] = [] }
      [layer, 0].uniq.each do |index|
        candidates(index) { |key| key.hold_mods.positive? }.each do |position, key|
          found[key.hold_mods] << position unless found[key.hold_mods].include?(position)
        end
      end
      found.sort_by { |mask, _| -mask.digits(2).sum }
    end

    def candidates(layer)
      @keymap.positions(layer).filter_map do |position|
        key, = @keymap.resolve(layer, position)
        [position, key] if yield(key)
      end
    end
  end
end
