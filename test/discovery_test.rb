# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class DiscoveryTest < Minitest::Test
  KEYBOARD = "\x05\x01\x09\x06\xA1\x01\x85\x01".b
  RAW = "\x06\x60\xFF\x09\x61\xA1\x01".b

  def device(name, vendor, product, descriptor, uniq: "", bus: 5)
    MkViewer::HidDevice.new(path: "/dev/x", name: name, bus: bus, vendor_id: vendor, product_id: product, uniq: uniq, descriptor: descriptor)
  end

  def config = MkViewer::Config.new(File.join(MkViewer::ROOT, "config/keyboards.yml"))

  def test_bluetooth_name_picks_the_keyboard_even_with_generic_ids
    assert_equal "kibard", config.profile_for(device("Kibard", 0x1D50, 0x615E, KEYBOARD)).id
    assert_nil config.profile_for(device("Corne", 0x1D50, 0x615E, KEYBOARD))
  end

  def test_usb_product_string_matches
    assert_equal "kibard", config.profile_for(device("ZMK Project Kibard", 0x1D50, 0x615E, KEYBOARD, bus: 3)).id
  end

  def test_voyager_needs_both_ids
    assert_equal "voyager", config.profile_for(device("ZSA Technology Labs Voyager", 0x3297, 0x1977, RAW)).id
    assert_nil config.profile_for(device("Other ZSA", 0x3297, 0x1978, RAW))
  end

  def test_interface_selection
    assert MkViewer::Protocols::Oryx.interface?(device("", 0, 0, RAW))
    refute MkViewer::Protocols::Oryx.interface?(device("", 0, 0, KEYBOARD))
    assert MkViewer::Protocols::ZmkLayerStatus.interface?(device("", 0, 0, KEYBOARD))
    refute MkViewer::Protocols::ZmkLayerStatus.interface?(device("", 0, 0, "\x05\x01\x09\x02\x85\x01".b))
  end

  def test_sysfs_parsing
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p("#{root}/hidraw3/device")
      File.write("#{root}/hidraw3/device/uevent", "HID_ID=0005:00001D50:0000615E\nHID_NAME=Kibard\nHID_UNIQ=e0:19\n")
      File.binwrite("#{root}/hidraw3/device/report_descriptor", KEYBOARD)
      found = MkViewer::HidDevice.all(sysfs: root).first
      assert_equal ["/dev/hidraw3", "Kibard", true, 0x1D50, "e0:19"], [found.path, found.name, found.bluetooth?, found.vendor_id, found.uniq]
    end
  end

  def test_most_recently_used_keyboard_is_current
    manager = MkViewer::Manager.new(config, devices: -> { [] })
    make = lambda do |activity|
      session = Object.new
      session.define_singleton_method(:last_activity) { activity }
      session
    end
    older = make.call(1)
    newer = make.call(2)
    manager.instance_variable_set(:@sessions, { "a" => older, "b" => newer })
    assert_same newer, manager.current
  end
end
