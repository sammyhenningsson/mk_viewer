# frozen_string_literal: true

require_relative "test_helper"

class HighlighterTest < Minitest::Test
  LSHIFT = 0x02
  R = 21
  N8 = 37

  def setup
    @highlighter = MkViewer::Highlighter.new(Fixtures.map)
  end

  def update(layer, keys, mods = 0) = @highlighter.update(layer, keys, mods).to_a.sort

  def test_plain_key
    assert_equal [0], update(0, [4])
    assert_equal [], update(0, [])
  end

  def test_held_modifier_finds_home_row_key
    assert_equal [1], update(0, [], LSHIFT)
  end

  def test_multi_bit_modifier_wins_over_its_parts
    assert_equal [2], update(0, [], 0x07)
  end

  def test_implied_shift_is_not_a_held_modifier
    assert_equal [2], update(1, [N8], LSHIFT), "LS(N8) on Nav, without lighting the Shift key"
  end

  def test_unshifted_variant_does_not_match_shifted_key
    assert_equal [7], update(1, [N8]), "plain N8 is inherited from Base, not the LS(N8) on Nav"
  end

  def test_implicit_modifier_needed_to_match
    assert_equal [], update(1, [25]), "V without Ctrl isn't the LC(V) key"
    assert_equal [3], update(1, [25], 0x01)
  end

  def test_key_stays_put_across_layer_change
    assert_equal [1], update(0, [R])
    assert_equal [1], update(1, [R])
  end

  def test_falls_back_to_base_layer
    assert_equal [0], update(1, [4])
  end

  def test_unknown_usage
    assert_equal [], update(0, [99])
  end
end
