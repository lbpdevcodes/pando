# frozen_string_literal: true

module Pando
  module Client
    # Backoff paces reconnect attempts: exponential growth to a cap, with downward
    # jitter so a fleet of clients doesn't reconnect in lockstep after a relay blip.
    class Backoff
      DEFAULT_JITTER = ->(delay) { delay * (0.5 + rand * 0.5) }

      def initialize(base: 1.0, cap: 60.0, jitter: DEFAULT_JITTER)
        @base = base
        @cap = cap
        @jitter = jitter
        reset
      end

      def next_delay
        delay = [@base * (2**@attempt), @cap].min
        @attempt += 1
        @jitter.call(delay)
      end

      def reset
        @attempt = 0
      end
    end
  end
end
