# frozen_string_literal: true

require "json"
require "open3"

module MkViewer
  # Battery levels of a Bluetooth keyboard, read from BlueZ over D-Bus with
  # busctl. A ZMK split with CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY has
  # one Battery Service per half: the central's first, then one per peripheral,
  # described "Peripheral 0" and so on. BlueZ's own Battery1 only shows the first.
  module Battery
    Level = Struct.new(:name, :percent)

    LEVEL_UUID = "00002a19-0000-1000-8000-00805f9b34fb"
    DESCRIPTION_UUID = "00002901-0000-1000-8000-00805f9b34fb"

    BUSCTL = lambda do |*args|
      out, status = Open3.capture2("busctl", "--system", "--json=short", "--timeout=5", *args, err: File::NULL)
      status.success? ? JSON.parse(out) : nil
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # Levels in the order the keyboard lists them, or [] if there are none to read.
    # labels: names for each level in that order, such as ["Left", "Right"].
    def self.levels(address, labels: nil, busctl: BUSCTL)
      objects = busctl.call("call", "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
      objects = objects&.dig("data", 0) or return []
      device = objects.find { |_, ifs| ifs.dig("org.bluez.Device1", "Address", "data").to_s.casecmp?(address) }
      return [] unless device

      characteristics(objects, device.first).each_with_index.filter_map do |(path, cached), index|
        read = busctl.call("call", "org.bluez", path, "org.bluez.GattCharacteristic1", "ReadValue", "a{sv}", "0")
        percent = read&.dig("data", 0, 0) || cached or next
        Level.new(labels&.[](index) || description(objects, path) || (index.zero? ? "Central" : "Battery #{index + 1}"),
                  percent)
      end
    end

    # [path, cached value] of each battery level characteristic, by handle.
    def self.characteristics(objects, device_path)
      objects.filter_map do |path, ifs|
        char = ifs["org.bluez.GattCharacteristic1"]
        next unless path.start_with?("#{device_path}/") && char&.dig("UUID", "data") == LEVEL_UUID

        [char.dig("Handle", "data").to_i, path, char.dig("Value", "data")&.first]
      end.sort.map { |_, path, value| [path, value] }
    end

    def self.description(objects, characteristic)
      objects.each do |path, ifs|
        desc = ifs["org.bluez.GattDescriptor1"]
        next unless path.start_with?("#{characteristic}/") && desc&.dig("UUID", "data") == DESCRIPTION_UUID

        return desc.dig("Value", "data").pack("C*").force_encoding(Encoding::UTF_8).scrub
      end
      nil
    end
  end
end
