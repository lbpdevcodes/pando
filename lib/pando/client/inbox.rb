# frozen_string_literal: true

module Pando
  module Client
    # Inbox turns an incoming relay Message frame back into content: opens the
    # envelope with this device's key, then acknowledges the frame so the relay can
    # forget it. Messages that fail to decrypt are NOT acked — they stay queued
    # rather than being silently lost.
    class Inbox
      Received = Data.define(:content, :from, :sender_key)

      def initialize(connection:, device:)
        @connection = connection
        @device = device
      end

      def receive(message_frame)
        envelope = Protocol::Envelope.from_h(message_frame.envelope)
        content = Protocol::Content.from_json(envelope.open(with: device))
        connection.ack(message_frame.seq)
        Received.new(content: content, from: envelope.from, sender_key: envelope.sender_key)
      end

      private

      attr_reader :connection, :device
    end
  end
end
