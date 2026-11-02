# frozen_string_literal: true

require_relative "test_helper"

class OryxKeymapTest < Minitest::Test
  def part(code, layer: nil, modifiers: nil, macro: nil)
    { "code" => code, "layer" => layer, "modifiers" => modifiers, "macro" => macro }
  end

  def test_builds_keys_in_layout_order
    layout = MkViewer::Layout.new([MkViewer::LayoutKey.new(x: 0, y: 0, oryx: 1), MkViewer::LayoutKey.new(x: 1, y: 0, oryx: 0)])
    revision = {
      "layers" => [
        { "position" => 1, "title" => "Nav", "keys" => [{ "tap" => part("KC_TRANSPARENT") }, { "tap" => part("KC_W", modifiers: { "leftCtrl" => true, "leftAlt" => false }) }] },
        { "position" => 0, "title" => "Base", "keys" => [{ "tap" => part("KC_N"), "hold" => part("MO", layer: 1) }, { "tap" => part("KC_TRANSPARENT", macro: {}), "customLabel" => "Save" }] }
      ]
    }
    map = MkViewer::Keymap::Oryx.new(revision, layout).map
    assert_equal %w[Base Nav], map.layers.map(&:name)
    assert_equal "Save", map.layers[0].keys[0].legend
    assert_equal %w[N Nav], [map.layers[0].keys[1].legend, map.layers[0].keys[1].hold]
    assert_equal 1, map.layers[0].keys[1].activates
    assert_equal "Ctrl W", map.layers[1].keys[0].legend
    assert map.layers[1].keys[1].transparent
  end

  def test_rejects_serial_without_revision
    assert_raises(MkViewer::Error) { MkViewer::Keymap::Oryx.load("default", MkViewer::Layout.new([])) }
  end
end
