# frozen_string_literal: true

module MkViewer
  # One /dev/hidrawN node, described from sysfs. For a Bluetooth keyboard, `name`
  # is its Bluetooth name and `uniq` its address; for USB, `name` is the product
  # string and `uniq` the serial number.
  HidDevice = Struct.new(:path, :name, :bus, :vendor_id, :product_id, :uniq, :descriptor, keyword_init: true) do
    def bluetooth? = bus == 0x05
    def transport = bluetooth? ? "Bluetooth" : "USB"

    # QMK's raw HID: usage page 0xFF60, usage 0x61.
    def raw_hid? = descriptor.start_with?("\x06\x60\xFF\x09\x61".b)

    # Generic Desktop / Keyboard, with report IDs (as ZMK's combined descriptor has).
    def report_id_keyboard? = descriptor.start_with?("\x05\x01\x09\x06".b) && descriptor.include?("\x85\x01".b)
  end

  class HidDevice
    SYSFS = "/sys/class/hidraw"

    def self.all(sysfs: SYSFS)
      Dir.glob(File.join(sysfs, "hidraw*")).sort.filter_map { |dir| from_sysfs(dir) }
    end

    def self.from_sysfs(dir)
      fields = File.read(File.join(dir, "device/uevent")).lines.to_h { |line| line.chomp.split("=", 2) }
      bus, vendor, product = fields.fetch("HID_ID").split(":").map { |hex| hex.to_i(16) }
      new(path: "/dev/#{File.basename(dir)}", name: fields["HID_NAME"].to_s, bus: bus, vendor_id: vendor,
          product_id: product, uniq: fields["HID_UNIQ"].to_s,
          descriptor: File.binread(File.join(dir, "device/report_descriptor")))
    rescue Errno::ENOENT, Errno::ENODEV, KeyError
      nil # it was unplugged while being read
    end
  end
end
