# frozen_string_literal: true

require "yaml"

module MkViewer
  LayoutKey = Struct.new(:x, :y, :matrix, :oryx, keyword_init: true)

  Layout = Struct.new(:keys) do
    def self.load(path)
      keys = YAML.safe_load_file(path).fetch("keys").map do |k|
        LayoutKey.new(x: k.fetch("x"), y: k.fetch("y"), matrix: k["matrix"], oryx: k["oryx"])
      end
      new(keys)
    end

    def position_for_matrix(row, col) = keys.index { |key| key.matrix == [row, col] }
  end

  Profile = Struct.new(:id, :name, :match, :protocol, :layout, :keymap, keyword_init: true) do
    def matches?(device)
      return false if match.empty?

      name_ok = !match["name"] || device.name.downcase.include?(match["name"].downcase)
      vendor_ok = !match["vendor_id"] || device.vendor_id == match["vendor_id"]
      product_ok = !match["product_id"] || device.product_id == match["product_id"]
      name_ok && vendor_ok && product_ok
    end

    def load_keymap(device)
      case keymap.fetch("type")
      when "zmk"
        Keymap::Zmk.load(File.expand_path(keymap.fetch("path")), labels: keymap["labels"] && File.expand_path(keymap["labels"]))
      when "oryx" then Keymap::Oryx.load(device.uniq, layout)
      else raise Error, "unknown keymap type #{keymap['type'].inspect}"
      end
    end
  end

  class Config
    DEFAULT_PATH = File.join(ROOT, "config/keyboards.yml")
    USER_PATH = File.join(ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")), "mk_viewer/keyboards.yml")

    attr_reader :profiles

    def self.load(path = nil)
      new(path || (File.exist?(USER_PATH) ? USER_PATH : DEFAULT_PATH))
    end

    def initialize(path)
      base = File.dirname(path)
      @profiles = YAML.safe_load_file(path).fetch("keyboards").map do |entry|
        Profile.new(id: entry.fetch("id"), name: entry["name"] || entry["id"], match: entry.fetch("match"),
                    protocol: entry.fetch("protocol"), keymap: entry.fetch("keymap"),
                    layout: Layout.load(File.expand_path(entry.fetch("layout"), base)))
      end
    end

    def profile_for(device) = profiles.find { |profile| profile.matches?(device) }
  end
end
