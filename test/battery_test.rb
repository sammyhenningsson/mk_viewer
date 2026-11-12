# frozen_string_literal: true

require_relative "test_helper"

class BatteryTest < Minitest::Test
  DEVICE = "/org/bluez/hci0/dev_E0_19_23_60_31_1B"

  def property(type, data) = { "type" => type, "data" => data }

  def level(handle, value)
    { "org.bluez.GattCharacteristic1" => { "Handle" => property("q", handle),
                                           "UUID" => property("s", MkViewer::Battery::LEVEL_UUID),
                                           "Value" => property("ay", [value]) } }
  end

  def objects
    {
      DEVICE => { "org.bluez.Device1" => { "Address" => property("s", "E0:19:23:60:31:1B") } },
      "#{DEVICE}/service0015/char0016" => level(22, 90),
      "#{DEVICE}/service0015/char0016/desc001a" => {
        "org.bluez.GattDescriptor1" => { "UUID" => property("s", MkViewer::Battery::DESCRIPTION_UUID),
                                         "Value" => property("ay", "Peripheral 0".bytes) }
      },
      "#{DEVICE}/service0010/char0011" => level(17, 70),
      "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0010/char0011" => level(17, 5)
    }
  end

  # Answers GetManagedObjects, and ReadValue from `reads` (path => level, nil for a failed read).
  def busctl(reads)
    lambda do |*args|
      next { "data" => [objects] } if args.include?("GetManagedObjects")

      value = reads.fetch(args[2])
      value && { "type" => "ay", "data" => [[value]] }
    end
  end

  def test_reads_each_level_in_handle_order
    levels = MkViewer::Battery.levels("e0:19:23:60:31:1b", busctl: busctl("#{DEVICE}/service0010/char0011" => 74,
                                                                          "#{DEVICE}/service0015/char0016" => 93))
    assert_equal [["Central", 74], ["Peripheral 0", 93]], levels.map(&:to_a)
  end

  def test_labels_and_cached_value_when_a_read_fails
    levels = MkViewer::Battery.levels("E0:19:23:60:31:1B", labels: %w[Left Right],
                                                           busctl: busctl("#{DEVICE}/service0010/char0011" => nil,
                                                                          "#{DEVICE}/service0015/char0016" => 93))
    assert_equal [["Left", 70], ["Right", 93]], levels.map(&:to_a)
  end

  def test_unknown_device_or_no_bus
    assert_equal [], MkViewer::Battery.levels("11:22:33:44:55:66", busctl: busctl({}))
    assert_equal [], MkViewer::Battery.levels("E0:19:23:60:31:1B", busctl: ->(*) {})
  end
end
