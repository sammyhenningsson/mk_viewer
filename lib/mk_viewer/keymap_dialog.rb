# frozen_string_literal: true

require "cgi"

module MkViewer
  # Asks which keymap file a ZMK keyboard uses. Reports through the block:
  # [:use, path], [:later] or [:never]. It isn't attached to the application, so
  # the app's single-letter shortcuts don't fire while typing a filename.
  class KeymapDialog
    def initialize(parent, keyboard:, first_time:, path: nil, &on_close)
      @on_close = on_close
      @window = Gtk::Window.new
      @window.title = first_time ? "New keyboard" : "Choose keymap"
      @window.transient_for = parent
      @window.modal = true
      @window.default_width = 520
      @window.child = build_content(keyboard, first_time, path)
      @closed = false
      @window.signal_connect("close-request") do
        finish(:later)
        false
      end
      @window.present
    end

    attr_reader :entry, :error

    # Checks the file, then saves it, or else explains what's wrong.
    def submit
      path = File.expand_path(@entry.text.strip)
      problem = problem_with(path)
      return @error.text = problem if problem

      finish(:use, path)
      @window.destroy
    end

    def choose(answer)
      finish(answer)
      @window.destroy
    end

    private

    def build_content(keyboard, first_time, path)
      box = Gtk::Box.new(:vertical, 12)
      %i[margin_top margin_bottom margin_start margin_end].each { |side| box.send("#{side}=", 18) }

      name = "<b>#{CGI.escapeHTML(keyboard)}</b>"
      question = first_time ? "#{name} is a ZMK keyboard mk_viewer hasn't seen before. Which keymap file does it use?" \
                            : "Which keymap file does #{name} use?"
      label = Gtk::Label.new
      label.markup = question
      label.wrap = true
      label.xalign = 0
      box.append(label)

      row = Gtk::Box.new(:horizontal, 8)
      @entry = Gtk::Entry.new
      @entry.hexpand = true
      @entry.text = path.to_s
      @entry.placeholder_text = "~/zmk-config/config/keyboard.keymap"
      @entry.signal_connect("activate") { submit }
      row.append(@entry)
      @browse = Gtk::Button.new(label: "Browse…")
      @browse.signal_connect("clicked") { browse }
      row.append(@browse)
      box.append(row)

      @error = Gtk::Label.new
      @error.wrap = true
      @error.xalign = 0
      box.append(@error)

      box.append(build_buttons(first_time))
      box
    end

    def build_buttons(first_time)
      buttons = Gtk::Box.new(:horizontal, 8)
      buttons.halign = :end
      @buttons = []
      if first_time
        add_button(buttons, "Never for this keyboard") { choose(:never) }
        add_button(buttons, "Not now") { choose(:later) }
      else
        add_button(buttons, "Cancel") { choose(:later) }
      end
      add_button(buttons, "Use keymap") { submit }.add_css_class("suggested-action")
      buttons
    end

    def add_button(box, label, &handler)
      button = Gtk::Button.new(label: label)
      button.signal_connect("clicked", &handler)
      box.append(button)
      @buttons << button
      button
    end

    def browse
      filter = Gtk::FileFilter.new
      filter.name = "ZMK keymaps"
      filter.add_pattern("*.keymap")
      filters = Gio::ListStore.new(Gtk::FileFilter)
      filters.append(filter)
      @file_dialog = Gtk::FileDialog.new
      @file_dialog.title = "Choose keymap"
      @file_dialog.filters = filters
      @file_dialog.open(@window) do |dialog, result|
        file = dialog.open_finish(result)
        @entry.text = file.path if file
      rescue StandardError
        nil # cancelled
      end
    end

    def problem_with(path)
      return "No file at #{path}" unless File.file?(path)

      layers = Keymap::Zmk.load(path).layers
      "That file has no layers." if layers.empty?
    rescue StandardError => e
      "That doesn't look like a ZMK keymap: #{e.message}"
    end

    def finish(*answer)
      return if @closed

      @closed = true
      @on_close.call(*answer)
    end
  end
end
