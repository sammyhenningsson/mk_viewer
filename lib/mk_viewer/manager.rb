# frozen_string_literal: true

require "set"

module MkViewer
  # Finds configured keyboards as they come and go, and picks the one to show:
  # whichever was used most recently.
  class Manager
    SCAN_INTERVAL = 2

    attr_reader :config, :problem

    def initialize(config, devices: -> { HidDevice.all })
      @config = config
      @devices = devices
      @sessions = {}
      @lock = Mutex.new
      @scan_lock = Mutex.new
      @unconfigured = []
      @dismissed = Set.new
    end

    def start
      @scanner = Thread.new do
        loop do
          scan
          sleep SCAN_INTERVAL
        end
      end
      self
    end

    def stop
      @scanner&.kill
      sessions.each(&:stop)
    end

    def sessions = @lock.synchronize { @sessions.values }

    def current = sessions.max_by(&:last_activity)

    # The next new ZMK keyboard to ask about, if any.
    def next_unconfigured
      @lock.synchronize { @unconfigured.find { |device| !@dismissed.include?(KeyboardStore.key(device.name)) } }
    end

    # Don't ask again until the app next starts.
    def dismiss(device)
      @lock.synchronize { @dismissed << KeyboardStore.key(device.name) }
    end

    def ignore(device)
      config.store.ignore(device.name)
      dismiss(device)
    end

    # Saves the keymap and reconnects the keyboard so it takes effect.
    def assign(device, path)
      config.store.assign(device.name, path)
      key = KeyboardStore.key(device.name)
      sessions.select { |session| KeyboardStore.key(session.device.name) == key }.each do |session|
        session.stop
        @lock.synchronize { @sessions.delete(session.device.path) }
      end
      scan
    end

    # Starts a session for each new matching interface and forgets dead ones.
    def scan
      @scan_lock.synchronize { scan_devices }
    end

    private

    def scan_devices
      problems = []
      @lock.synchronize do
        @sessions.each do |path, session|
          next if session.alive?

          problems << "#{session.profile.name}: #{session.error}" if session.error
          @sessions.delete(path)
        end
      end
      devices = @devices.call
      unconfigured = devices.select { |device| config.unconfigured?(device) }
      @lock.synchronize { @unconfigured = unconfigured }
      devices.each do |device|
        profile = config.profile_for(device) or next
        next unless Session.protocol_class(profile).interface?(device)
        next if @lock.synchronize { @sessions.key?(device.path) }

        session = Session.new(profile, device).start
        @lock.synchronize { @sessions[device.path] = session }
      end
      @problem = problems.first
    end
  end
end
