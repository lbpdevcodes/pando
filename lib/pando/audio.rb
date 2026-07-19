# frozen_string_literal: true

module Pando
  # Audio holds pando's recording side (playback reuses Charming::Audio::Player).
  # The recorder_factory seam lets journeys substitute a fake recorder that
  # "records" a fixture instead of spawning a real capture process.
  module Audio
    class << self
      attr_writer :recorder_factory

      def recorder_factory
        @recorder_factory ||= -> { Recorder.new }
      end

      def build_recorder
        recorder_factory.call
      end
    end
  end
end
