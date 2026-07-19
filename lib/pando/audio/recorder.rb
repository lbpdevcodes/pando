# frozen_string_literal: true

require "fileutils"

module Pando
  module Audio
    # Recorder captures a voice note by spawning a system capture binary,
    # modeled on Charming::Audio::Player's adapter pattern: the injected
    # Charming::Audio::System is the only thing touching the process table, so
    # specs fake the adapter, never Process. Output is WAV 16 kHz mono — the
    # one format every Player backend plays.
    #
    # Stop is SIGTERM, not SIGKILL: sox and ffmpeg finalize the WAV header on
    # TERM. An at_exit guard reaps the child even if the app dies mid-recording
    # (the UI's task thread is hard-killed shortly after quit).
    class Recorder
      Unavailable = Class.new(StandardError)
      AlreadyRecording = Class.new(StandardError)

      # `rec` (sox) first — its capture device handling is the least fiddly.
      # ffmpeg's device flag differs per OS; pw-record covers PipeWire-only
      # Linux setups.
      BACKENDS = [
        {command: "rec", os: :any,
         argv: ->(path) { ["rec", "-q", "-r", "16000", "-c", "1", path] }},
        {command: "ffmpeg", os: :macos,
         argv: ->(path) {
           ["ffmpeg", "-hide_banner", "-loglevel", "quiet", "-f", "avfoundation",
             "-i", ":default", "-ac", "1", "-ar", "16000", "-y", path]
         }},
        {command: "ffmpeg", os: :linux,
         argv: ->(path) {
           ["ffmpeg", "-hide_banner", "-loglevel", "quiet", "-f", "pulse",
             "-i", "default", "-ac", "1", "-ar", "16000", "-y", path]
         }},
        {command: "pw-record", os: :linux,
         argv: ->(path) { ["pw-record", "--rate", "16000", "--channels", "1", path] }}
      ].freeze

      MAX_SECONDS = 180

      attr_reader :system, :path

      def initialize(system: Charming::Audio::System.new)
        @system = system
        @pid = nil
        @started_at = nil
      end

      def start(path)
        raise AlreadyRecording, "already recording to #{@path}" if recording?

        backend = resolve_backend!
        @path = path
        @pid = system.spawn(backend[:argv].call(path))
        @started_at = monotonic_now
        install_exit_guard
        @pid
      end

      def stop
        return unless @pid

        system.terminate(@pid)
        system.wait(@pid)
        @pid = nil
        @started_at = nil
      end

      def cancel
        stop
        FileUtils.rm_f(@path) if @path
      end

      def recording?
        !@pid.nil? && system.alive?(@pid)
      end

      def elapsed
        return 0 unless @started_at

        (monotonic_now - @started_at).floor
      end

      def available?
        !find_backend.nil?
      end

      private

      def resolve_backend!
        find_backend || raise(Unavailable, "no capture backend found (install sox, ffmpeg, or pipewire)")
      end

      def find_backend
        BACKENDS.find do |backend|
          os_matches?(backend[:os]) && system.which?(backend[:command])
        end
      end

      def os_matches?(os)
        os == :any || (os == :macos && system.macos?) || (os == :linux && system.linux?)
      end

      def install_exit_guard
        return if @exit_guard_installed

        @exit_guard_installed = true
        at_exit { stop }
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
