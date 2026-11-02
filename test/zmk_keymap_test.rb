# frozen_string_literal: true

require_relative "test_helper"

class ZmkKeymapTest < Minitest::Test
  def setup
    @map = Fixtures.map
    @base, @nav = @map.layers.map(&:keys)
  end

  def test_layer_names_and_comments
    assert_equal %w[Base Nav], @map.layers.map(&:name)
    assert_equal 8, @base.size, "the comment's &kp Q must not become a key"
  end

  def test_hold_tap
    key = @base[1]
    assert_equal ["R", "Shift", 0x02], [key.legend, key.hold, key.hold_mods]
    assert_equal 21, key.usage
  end

  def test_combined_modifier_define
    assert_equal 0x07, @base[2].hold_mods
  end

  def test_adaptive_key_uses_inner_binding_and_label
    assert_equal ["E!", "Shift", 8, 0x20], [@base[3].legend, @base[3].hold, @base[3].usage, @base[3].hold_mods]
  end

  def test_layer_tap_names_the_layer
    assert_equal ["⏎", "Nav"], [@base[4].legend, @base[4].hold]
    assert_equal 0, @base[4].hold_mods
  end

  def test_function_macro
    assert_equal ["J", 13, 0], [@base[5].legend, @base[5].usage, @base[5].hold_mods]
    assert_equal "⇧J", @base[5].hold
  end

  def test_implicit_modifiers_and_labels
    assert_equal ["@", 31, 0x40], [@nav[1].legend, @nav[1].usage, @nav[1].mods]
    assert_equal ["Ctrl V", 0x01], [@nav[3].legend, @nav[3].mods]
    assert_equal "→ Base", @nav[4].legend
    assert_nil @nav[5].usage, "media keys aren't in the keyboard report"
  end

  def test_transparent_resolves_downward
    key, inherited = @map.resolve(1, 0)
    assert_equal "A", key.legend
    assert inherited
    assert_equal [false], @map.resolve(1, 1).last(1)
  end

  def test_none_stops_transparency
    assert @base[6].blank?
    refute @base[6].transparent
  end
end
