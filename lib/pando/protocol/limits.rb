# frozen_string_literal: true

module Pando
  module Protocol
    # Limits are the relay's advertised capacity rules, shared with clients so both
    # sides agree on what a send may weigh and how long a queued message survives.
    Limits = Data.define(:max_queued_messages, :max_queued_bytes, :max_frame_bytes, :queue_ttl) do
      def self.default
        new(
          max_queued_messages: 512,
          max_queued_bytes: 16 * 1024 * 1024,
          max_frame_bytes: 256 * 1024,
          queue_ttl: 24 * 60 * 60
        )
      end
    end
  end
end
