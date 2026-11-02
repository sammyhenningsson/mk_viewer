# frozen_string_literal: true

require_relative "test_helper"

class ProtocolsTest < Minitest::Test
  def layout(keys) = MkViewer::Layout.new(keys)

  def session(protocol, layout_keys)
    profile = MkViewer::Profile.new(id: "t", name: "T", match: {}, protocol: protocol, layout: layout(layout_keys), keymap: {})
    device = MkViewer::HidDevice.new(path: "/dev/null", name: "T", bus: 5, vendor_id: 0, product_id: 0, uniq: "", descriptor: "")
    @now = 100.0
    MkViewer::Session.new(profile, device, clock: -> { @now })
  end

  def report(*bytes) = bytes + [0] * (32 - bytes.size)

  def voyager_session
    session("oryx", [
              MkViewer::LayoutKey.new(x: 0, y: 0, matrix: [0, 1]),
              MkViewer::LayoutKey.new(x: 1, y: 0, matrix: [6, 0])
            ])
  end

  def test_oryx_layer
    s = voyager_session
    s.receive(report(5, 3, 0xFE))
    assert_equal 3, s.layer
  end

  def test_oryx_key_events_are_col_then_row
    s = voyager_session
    s.receive(report(6, 0, 6, 0xFE))
    assert_equal [0.0, 1.0], s.view.keys.map(&:heat)
    s.receive(report(7, 0, 6, 0xFE))
    assert_equal 1.0, s.view.keys[1].heat, "lingers at the moment of release"
    @now += 1
    assert_equal [0.0, 0.0], s.view.keys.map(&:heat)
  end

  def test_oryx_handshake_prefixes_report_id
    written = nil
    io = Object.new
    io.define_singleton_method(:syswrite) { |data| written = data }
    MkViewer::Protocols::Oryx.new(voyager_session).handshake(io)
    assert_equal [0, 1], written.bytes.first(2)
    assert_equal 33, written.bytesize
  end

  def zmk_session
    s = session("zmk_layer_status", Array.new(8) { |i| MkViewer::LayoutKey.new(x: i, y: 0) })
    s.instance_variable_set(:@keymap, Fixtures.map)
    s
  end

  def test_zmk_report_sets_layer_and_highlight
    s = zmk_session
    s.receive([1, 0, 1, 19, 0, 0, 0, 0, 0]) # layer 1 has no P; nothing lights
    assert_equal 1, s.layer
    assert_equal 0.0, s.view.keys.map(&:heat).max
    s.receive([1, 0x40, 1, 31, 0, 0, 0, 0, 0])
    assert_equal 1.0, s.view.keys[1].heat
  end

  def test_zmk_ignores_other_reports
    s = zmk_session
    s.layer = 2
    s.receive([2, 9, 9, 9, 9, 9, 9, 9, 9])
    s.receive([1, 0, 7])
    assert_equal 2, s.layer
  end

  def test_view_shows_layer_names
    s = zmk_session
    s.receive([1, 0, 1, 0, 0, 0, 0, 0, 0])
    view = s.view
    assert_equal %w[Base Nav], view.layer_names
    assert_equal "A", view.keys[0].legend
    assert view.keys[0].inherited
    assert_equal "@", view.keys[1].legend
  end
end
