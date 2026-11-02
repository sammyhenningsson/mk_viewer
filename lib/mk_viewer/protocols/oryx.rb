# frozen_string_literal: true

module MkViewer
  module Protocols
    # ZSA's Oryx raw HID protocol, as used by Keymapp's live view. It reports the
    # layer and each key's matrix position, so highlighting is exact.
    # https://github.com/zsa/qmk_modules/blob/main/oryx/oryx.h
    class Oryx
      CMD_PAIRING_INIT = 1
      EVT_LAYER = 5
      EVT_KEYDOWN = 6
      EVT_KEYUP = 7
      REPORT_SIZE = 32

      def self.interface?(device) = device.raw_hid?

      def initialize(session)
        @session = session
      end

      # Events only flow once paired. Pairing also makes the firmware send the
      # current layer. The leading zero is the report ID hidraw expects.
      def handshake(io)
        io.syswrite(([0, CMD_PAIRING_INIT] + [0] * (REPORT_SIZE - 1)).pack("C*"))
      end

      def receive(bytes)
        case bytes[0]
        when EVT_LAYER then @session.layer = bytes[1]
        when EVT_KEYDOWN, EVT_KEYUP
          position = @session.profile.layout.position_for_matrix(bytes[2], bytes[1])
          @session.set_key(position, bytes[0] == EVT_KEYDOWN) if position
        end
      end
    end
  end
end
