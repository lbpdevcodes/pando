# frozen_string_literal: true

module Pando
  # Sweeping is the client half of self-destruct: a 1 Hz background tick that
  # purges expired message rows and repaints only when something vanished.
  # Correctness never depends on it — Message.unexpired scopes every read —
  # the sweeper's job is making rows (and their ciphertext) actually go away.
  # Same threading rules as Connectivity: only under a threaded executor.
  module Sweeping
    def self.included(base)
      base.on_task_progress :sweeper, action: :handle_sweep_tick
      base.before_action :ensure_sweeping
    end

    def handle_sweep_tick
      return unless Store.unlocked?
      return if Message.sweep_expired.zero?

      render_default_action
    end

    private

    def ensure_sweeping
      return if session[:sweeper_started]
      return unless application.task_executor.is_a?(Charming::Tasks::ThreadedExecutor)

      session[:sweeper_started] = true
      run_task(:sweeper) do |progress|
        tick = 0
        loop do
          sleep 1
          progress.report(tick += 1)
        end
      end
    end
  end
end
