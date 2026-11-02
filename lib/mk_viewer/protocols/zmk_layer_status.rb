# frozen_string_literal: true

module MkViewer
  module Protocols
    # ZMK with CONFIG_ZMK_LAYER_STATUS_BLE_HID, which puts the active layer in the
    # reserved byte of the normal keyboard report, over both Bluetooth and USB:
    #
    #   [report id = 1] [modifiers] [layer] [up to 6 keycodes]
    #
    # Reports only carry keycodes, so positions come from the keymap (see Highlighter).
    class ZmkLayerStatus
      KEYBOARD_REPORT = 1
      REPORT_SIZE = 9

      def self.interface?(device) = device.report_id_keyboard?

      def initialize(session)
        @session = session
        @highlighter = nil
      end

      def handshake(_io); end

      def receive(bytes)
        return unless bytes[0] == KEYBOARD_REPORT && bytes.size >= REPORT_SIZE

        _, mods, layer, *keys = bytes.first(REPORT_SIZE)
        @session.layer = layer
        keymap = @session.keymap or return

        @highlighter ||= Highlighter.new(keymap)
        @session.pressed = @highlighter.update(layer, keys.reject(&:zero?), mods)
      end
    end
  end
end
