# frozen_string_literal: true

module MkViewer
  ROOT = File.expand_path("..", __dir__)
  Error = Class.new(StandardError)
end

require_relative "mk_viewer/keycodes"
require_relative "mk_viewer/keymap/model"
require_relative "mk_viewer/keymap/zmk"
require_relative "mk_viewer/keymap/oryx"
require_relative "mk_viewer/hid_device"
require_relative "mk_viewer/keyboard_store"
require_relative "mk_viewer/config"
require_relative "mk_viewer/highlighter"
require_relative "mk_viewer/protocols/oryx"
require_relative "mk_viewer/protocols/zmk_layer_status"
require_relative "mk_viewer/session"
require_relative "mk_viewer/manager"
