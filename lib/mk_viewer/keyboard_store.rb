# frozen_string_literal: true

require "fileutils"
require "yaml"

module MkViewer
  # Remembers what the user chose for each ZMK keyboard, by name: its keymap file,
  # or that they never want to be asked. A board's USB product string is its
  # Bluetooth name with a maker prefix, so both connections share one entry.
  class KeyboardStore
    PATH = File.join(ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")), "mk_viewer/zmk_keyboards.yml")

    def self.display_name(name) = name.sub(/\AZMK Project\s+/i, "").strip
    def self.key(name) = display_name(name).downcase

    def initialize(path = PATH)
      @path = path
      @lock = Mutex.new
      @entries = File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
    end

    def keymap_for(name) = @lock.synchronize { @entries.dig(self.class.key(name), "keymap") }
    def ignored?(name) = @lock.synchronize { @entries.dig(self.class.key(name), "ignored") == true }

    def assign(name, path) = save(name, { "keymap" => File.expand_path(path) })
    def ignore(name) = save(name, { "ignored" => true })

    private

    def save(name, entry)
      @lock.synchronize do
        @entries[self.class.key(name)] = entry
        FileUtils.mkdir_p(File.dirname(@path))
        temporary = "#{@path}.tmp"
        File.write(temporary, @entries.to_yaml)
        File.rename(temporary, @path)
      end
    end
  end
end
