# frozen_string_literal: true

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

    # Starts a session for each new matching interface and forgets dead ones.
    def scan
      problems = []
      @lock.synchronize do
        @sessions.each do |path, session|
          next if session.alive?

          problems << "#{session.profile.name}: #{session.error}" if session.error
          @sessions.delete(path)
        end
      end
      @devices.call.each do |device|
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
