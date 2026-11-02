# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ZmkOnboardingTest < Minitest::Test
  KEYBOARD = "\x05\x01\x09\x06\xA1\x01\x85\x01".b
  CONFIG = File.join(MkViewer::ROOT, "config/keyboards.yml")

  def setup
    @dir = Dir.mktmpdir
    @store_path = File.join(@dir, "sub/store.yml")
    @keymap = File.join(@dir, "corne.keymap")
    File.write(@keymap, Fixtures::KEYMAP)
    @config = MkViewer::Config.new(CONFIG, store: MkViewer::KeyboardStore.new(@store_path))
  end

  def teardown = FileUtils.remove_entry(@dir)

  def device(name = "Corne", path: "/dev/x")
    MkViewer::HidDevice.new(path: path, name: name, bus: 5, vendor_id: 0x1D50, product_id: 0x615E, uniq: "", descriptor: KEYBOARD)
  end

  def manager(*devices) = MkViewer::Manager.new(@config, devices: -> { devices })

  def test_new_zmk_keyboard_is_unconfigured
    assert @config.unconfigured?(device)
    assert_nil @config.profile_for(device)
  end

  def test_keyboards_that_should_not_ask
    refute @config.unconfigured?(device("Kibard")), "already has a config entry"
    other = device
    other.vendor_id = 0x3297
    refute @config.unconfigured?(other), "not a ZMK keyboard"
    mouse = device
    mouse.descriptor = "\x05\x01\x09\x02\x85\x01".b
    refute @config.unconfigured?(mouse), "not the keyboard interface"
  end

  def test_choice_builds_a_profile_and_is_remembered
    @config.store.assign("Corne", @keymap)
    profile = @config.profile_for(device)
    assert_equal ["Corne", @keymap, "zmk_layer_status"], [profile.name, profile.keymap["path"], profile.protocol]
    assert_equal 8, profile.layout.keys.size
    assert_same profile, @config.profile_for(device), "not rebuilt on every scan"
    refute @config.unconfigured?(device)

    reopened = MkViewer::KeyboardStore.new(@store_path)
    assert_equal @keymap, reopened.keymap_for("Corne")
  end

  def test_usb_and_bluetooth_names_share_a_choice
    @config.store.assign("Corne", @keymap)
    assert_equal "Corne", @config.profile_for(device("ZMK Project Corne")).name
  end

  def test_missing_file_asks_again
    @config.store.assign("Corne", File.join(@dir, "gone.keymap"))
    assert_nil @config.profile_for(device)
    assert @config.unconfigured?(device)
  end

  def test_choice_overrides_a_configured_keyboards_file
    original = @config.profile_for(device("Kibard"))
    @config.store.assign("Kibard", @keymap)
    changed = @config.profile_for(device("Kibard"))
    assert_equal @keymap, changed.keymap["path"]
    assert_equal original.keymap["labels"], changed.keymap["labels"]
    assert_same original.layout, changed.layout
    refute_equal @keymap, original.keymap["path"]
  end

  def test_voyager_ignores_a_stored_choice
    voyager = MkViewer::HidDevice.new(path: "/dev/y", name: "ZSA Technology Labs Voyager", bus: 3, vendor_id: 0x3297, product_id: 0x1977, uniq: "", descriptor: "")
    @config.store.assign(voyager.name, @keymap)
    assert_equal "oryx", @config.profile_for(voyager).keymap["type"]
  end

  def test_manager_asks_until_dismissed
    m = manager(device)
    m.scan
    assert_equal "Corne", m.next_unconfigured.name
    m.dismiss(device)
    m.scan
    assert_nil m.next_unconfigured
    assert @config.unconfigured?(device), "only dismissed for this run"
  end

  def test_never_is_remembered
    m = manager(device)
    m.scan
    m.ignore(device)
    m.scan
    assert_nil m.next_unconfigured
    assert MkViewer::KeyboardStore.new(@store_path).ignored?("Corne")
  end

  def test_assign_starts_a_session
    m = manager(device(path: "/dev/null"))
    m.scan
    m.assign(device, @keymap)
    assert_nil m.next_unconfigured
    assert_equal ["Corne"], m.sessions.map { |s| s.profile.name }
  ensure
    m&.stop
  end

  def test_geometry_keeps_columns_and_split
    source = <<~DTS
      / { keymap { compatible = "zmk,keymap"; base { bindings = <
        &kp A  &kp B            &kp C  &kp D
               &kp E            &kp F
      >; }; }; };
    DTS
    assert_equal [[0.0, 0.0], [1.0, 0.0], [3.0, 0.0], [4.0, 0.0], [1.0, 1.0], [3.0, 1.0]],
                 MkViewer::Keymap::Zmk.new(source).geometry
  end

  def test_geometry_falls_back_to_a_grid_for_one_line
    source = %(/ { keymap { base { bindings = < #{(['&kp A'] * 12).join(' ')} >; }; }; };)
    positions = MkViewer::Keymap::Zmk.new(source).geometry
    assert_equal 12, positions.size
    assert_equal positions.size, positions.uniq.size
  end
end
