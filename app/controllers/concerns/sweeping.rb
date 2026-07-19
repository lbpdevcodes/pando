# frozen_string_literal: true

module Pando
  # Sweeping is the client half of self-destruct: a 1 Hz timer purges expired
  # message rows and repaints only when something vanished. Correctness never
  # depends on it — Message.unexpired scopes every read — the sweeper's job is
  # making rows (and their ciphertext) actually go away.
  #
  # This MUST be a charming timer, not a background task with progress
  # reports: timers skip the repaint when the action responds with nil, while
  # task-progress dispatches fall back to render("") — a silent tick would
  # wipe the screen (and any open modal) every second.
  module Sweeping
    def self.included(base)
      base.timer :sweep, every: 1, action: :handle_sweep_tick
    end

    def handle_sweep_tick
      return unless Store.unlocked?
      return if Message.sweep_expired.zero?

      render_default_action
    end
  end
end
