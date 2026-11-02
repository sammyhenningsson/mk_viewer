# frozen_string_literal: true

require "set"

module MkViewer
  # A connected keyboard: a reader thread feeding its protocol, plus the current
  # state. Nothing the keyboard sends is logged or stored; only the currently
  # pressed positions are kept, in memory.
  class Session
    PROTOCOLS = { "oryx" => Protocols::Oryx, "zmk_layer_status" => Protocols::ZmkLayerStatus }.freeze
    LINGER = 0.22 # seconds a key stays lit after release: tap-holds send press and release together

    ViewKey = Struct.new(:x, :y, :legend, :hold, :shifted, :inherited, :heat, keyword_init: true)
    View = Struct.new(:title, :transport, :layer, :layer_names, :keys, :message, keyword_init: true)

    attr_reader :profile, :device, :error, :last_activity

    def self.protocol_class(profile)
      PROTOCOLS.fetch(profile.protocol) { raise Error, "unknown protocol #{profile.protocol.inspect}" }
    end

    def initialize(profile, device, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @profile = profile
      @device = device
      @clock = clock
      @lock = Mutex.new
      @layer = 0
      @down = Set.new
      @released = {}
      @last_activity = 0
      @protocol = self.class.protocol_class(profile).new(self)
    end

    def keymap = @lock.synchronize { @keymap }
    def layer = @lock.synchronize { @layer }
    def alive? = @thread&.alive?

    def layer=(value)
      @lock.synchronize { @layer = value }
    end

    def pressed=(positions)
      @lock.synchronize do
        now = @clock.call
        (@down - positions).each { |position| @released[position] = now }
        positions.each { |position| @released.delete(position) }
        @down = positions.to_set
      end
    end

    def set_key(position, down)
      self.pressed = down ? @down | [position] : @down - [position]
    end

    def receive(bytes)
      @lock.synchronize { @last_activity = @clock.call }
      @protocol.receive(bytes)
    end

    def start
      @thread = Thread.new do
        Thread.current.report_on_exception = false
        load_keymap
        read_loop
      end
      self
    end

    def stop
      @thread&.kill
      @thread&.join(1)
    end

    def view(highlight: true)
      @lock.synchronize do
        now = @clock.call
        @released.delete_if { |_, time| now - time > LINGER }
        names = @keymap ? @keymap.layers.map(&:name) : []
        View.new(title: profile.name, transport: device.transport, layer: @layer, layer_names: names,
                 keys: view_keys(now, highlight), message: @keymap ? nil : @keymap_error || "Loading keymap…")
      end
    end

    private

    def view_keys(now, highlight)
      profile.layout.keys.each_with_index.map do |geometry, position|
        key, inherited = @keymap ? @keymap.resolve(@layer, position) : [Keymap::TRANSPARENT, false]
        ViewKey.new(x: geometry.x, y: geometry.y, legend: key.legend.to_s, hold: key.hold.to_s, shifted: key.shifted.to_s,
                    inherited: inherited, heat: highlight ? heat(position, now) : 0.0)
      end
    end

    def heat(position, now)
      return 1.0 if @down.include?(position)

      released = @released[position] or return 0.0
      (1.0 - (now - released) / LINGER).clamp(0.0, 1.0).round(2)
    end

    def load_keymap
      map = profile.load_keymap(device)
      @lock.synchronize { @keymap = map }
    rescue StandardError => e
      # Still report the layer number and connection if the keymap can't load.
      @lock.synchronize { @keymap_error = "Keymap unavailable: #{e.message}" }
    end

    def read_loop
      File.open(device.path, File::RDWR | File::NONBLOCK) do |io|
        @protocol.handshake(io)
        loop do
          IO.select([io])
          begin
            receive(io.read_nonblock(64).bytes)
          rescue IO::WaitReadable
            next
          end
        end
      end
    rescue Errno::ENODEV, Errno::EIO, EOFError
      nil # disconnected
    rescue SystemCallError => e
      @error = e.message
    end
  end
end
