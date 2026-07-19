# frozen_string_literal: true

module Pando
  module Relay
    # Rendezvous brokers invite exchanges: two parties who share a short code each
    # deposit an encrypted identity blob in the code's slot and poll for the other's.
    # Slots hold at most two payloads and expire quickly; they are deliberately
    # memory-only — a relay restart just means retrying the exchange.
    class Rendezvous
      SlotFull = Class.new(StandardError)

      Slot = Data.define(:payloads, :expires_at)

      def initialize(ttl: 300)
        @ttl = ttl
        @slots = {}
        @mutex = Mutex.new
      end

      def deposit(code, payload, now:)
        @mutex.synchronize do
          slot = live_slot(code, now) || Slot.new(payloads: [], expires_at: now + ttl)
          raise SlotFull, "rendezvous slot already has two payloads" if slot.payloads.length >= 2

          @slots[code] = Slot.new(payloads: slot.payloads + [payload], expires_at: slot.expires_at)
        end
      end

      def fetch(code, now:)
        @mutex.synchronize { live_slot(code, now)&.payloads || [] }
      end

      def delete(code)
        @mutex.synchronize { @slots.delete(code) }
      end

      private

      attr_reader :ttl

      def live_slot(code, now)
        slot = @slots[code]
        return nil unless slot
        return @slots.delete(code) && nil if now >= slot.expires_at

        slot
      end
    end
  end
end
