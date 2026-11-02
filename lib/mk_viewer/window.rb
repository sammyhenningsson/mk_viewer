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

    def build(application)
      area = Gtk::DrawingArea.new
      window = Gtk::ApplicationWindow.new(application)
      window.title = "Keyboard layers"
      window.set_default_size(980, 460)
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

    def tick(area, window)
      current = @manager.current
      view = current&.view
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
