# frozen_string_literal: true

require "gtk4"
require_relative "renderer"
require_relative "keymap_dialog"

module MkViewer
  # The GTK window. Polls the manager and redraws only when the picture changes.
  class Window
    TICK_MS = 16

    def initialize(manager)
      @manager = manager
    end

    def run
      app = Gtk::Application.new("dev.mkviewer.MkViewer", :default_flags)
      app.signal_connect("activate") { |application| build(application) }
      app.run([])
    end

    private

    # Widgets are kept in instance variables on purpose. Ruby can garbage collect
    # a widget's wrapper while GTK still shows the widget, and that silently drops
    # its signal handlers.
    def build(application)
      # Launching the app again re-activates this running instance.
      return @window.present if @window

      area = @area = Gtk::DrawingArea.new
      window = @window = Gtk::ApplicationWindow.new(application)
      window.title = "Keyboard layers"
      window.set_default_size(980, 460)
      window.titlebar = build_header
      window.child = area
      add_shortcuts(application)
      follow_system_theme

      area.set_draw_func do |_widget, cr, width, height|
        @renderer.draw(cr, width, height, @view, connected: @others || [], problem: @problem)
      end

      GLib::Timeout.add(TICK_MS) do
        tick(area, window)
        GLib::Source::CONTINUE
      end
      window.signal_connect("close-request") do
        @manager.stop
        false
      end
      window.present
    end

    def add_shortcuts(application)
      @actions = []
      add_shortcut(application, "quit", "<Control>q") { application.quit }
      add_shortcut(application, "toggle-highlight", "t") do
        @highlight_switch.active = !@highlight_switch.active?
      end
    end

    def add_shortcut(application, name, accelerator, &handler)
      action = Gio::SimpleAction.new(name)
      action.signal_connect("activate", &handler)
      application.add_action(action)
      application.set_accels_for_action("app.#{name}", [accelerator])
      @actions << action
    end

    def build_header
      @highlight_switch = Gtk::Switch.new
      @highlight_switch.active = true
      @highlight_switch.valign = :center
      # Not focusable, so pressing Space or Enter while testing keys can't flip it.
      @highlight_switch.focusable = false

      box = Gtk::Box.new(:horizontal, 8)
      box.append(Gtk::Label.new("Highlight keys"))
      box.append(@highlight_switch)

      @keymap_button = Gtk::Button.new(label: "Keymap…")
      @keymap_button.tooltip_text = "Choose the keymap file for this keyboard"
      @keymap_button.focusable = false
      @keymap_button.signal_connect("clicked") { change_keymap }

      header = Gtk::HeaderBar.new
      header.pack_start(box)
      header.pack_end(@keymap_button)
      header
    end

    # GTK keeps this setting in sync with the desktop's light/dark preference, but
    # plain GTK doesn't always restyle itself to match: a theme name like "Adw-dark"
    # only exists with libadwaita, and GTK falls back to its light theme. So the
    # setting is applied to the window frame here, as well as the drawing.
    def follow_system_theme
      dark = system_dark?
      return false if dark == @dark

      @dark = dark
      @renderer = Renderer.new(dark: dark)
      settings.gtk_application_prefer_dark_theme = dark
      true
    end

    def system_dark?
      settings.get_property("gtk-interface-color-scheme").nick == "dark"
    end

    def settings = @settings ||= Gtk::Settings.default

    def ask_about_new_keyboard
      return if @dialog

      device = @manager.next_unconfigured or return
      @dialog = KeymapDialog.new(@window, keyboard: KeyboardStore.display_name(device.name), first_time: true) do |answer, path|
        @dialog = nil
        case answer
        when :use then @manager.assign(device, path)
        when :never then @manager.ignore(device)
        else @manager.dismiss(device)
        end
      end
    end

    def change_keymap
      session = @manager.current
      return if @dialog || !session || session.profile.keymap["type"] != "zmk"

      @dialog = KeymapDialog.new(@window, keyboard: session.profile.name, first_time: false,
                                          path: session.profile.keymap["path"]) do |answer, path|
        @dialog = nil
        @manager.assign(session.device, path) if answer == :use
      end
    end

    def tick(area, window)
      area.queue_draw if follow_system_theme
      ask_about_new_keyboard

      current = @manager.current
      @keymap_button.sensitive = current&.profile&.keymap&.fetch("type") == "zmk"
      view = current&.view(highlight: @highlight_switch.active?)
      others = @manager.sessions.reject { |s| s.equal?(current) }.map { |s| s.profile.name }.uniq
      problem = @manager.problem
      return if view == @view && others == @others && problem == @problem

      @view = view
      @problem = problem
      @others = others
      window.title = view ? "#{view.title} — #{view.layer_names[view.layer] || "Layer #{view.layer}"}" : "Keyboard layers"
      area.queue_draw
    end
  end
end
