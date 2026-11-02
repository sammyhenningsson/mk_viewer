# frozen_string_literal: true

require "gtk4"
require_relative "renderer"

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
      renderer = nil

      area.set_draw_func do |widget, cr, width, height|
        renderer ||= Renderer.new(dark: dark?(widget))
        renderer.draw(cr, width, height, @view, connected: @others || [], problem: @problem)
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

    def build_header
      @highlight_switch = Gtk::Switch.new
      @highlight_switch.active = true
      @highlight_switch.valign = :center
      # Not focusable, so pressing Space or Enter while testing keys can't flip it.
      @highlight_switch.focusable = false

      box = Gtk::Box.new(:horizontal, 8)
      box.append(Gtk::Label.new("Highlight keys"))
      box.append(@highlight_switch)

      header = Gtk::HeaderBar.new
      header.pack_start(box)
      header
    end

    def tick(area, window)
      current = @manager.current
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

    def dark?(widget)
      color = widget.color
      color.red * 0.3 + color.green * 0.6 + color.blue * 0.1 > 0.5
    rescue NoMethodError
      true
    end
  end
end
