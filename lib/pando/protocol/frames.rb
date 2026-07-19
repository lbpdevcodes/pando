# frozen_string_literal: true

require "json"

module Pando
  module Protocol
    # Frames are the relay's WebSocket vocabulary: JSON text frames tagged with a
    # version and type. The relay reads only these — envelopes ride inside them as
    # opaque hashes. Unknown types, versions, or malformed JSON raise UnknownFrame.
    module Frames
      UnknownFrame = Class.new(StandardError)

      VERSION = 1

      # Adds the wire encoding shared by every frame type.
      module Encodable
        def encode
          JSON.generate({"v" => VERSION, "t" => Frames.type_of(self.class)}.merge(to_h.transform_keys(&:to_s)))
        end
      end

      Challenge = Data.define(:nonce) { include Encodable }
      Subscribe = Data.define(:mailbox, :device_key, :sig) { include Encodable }
      Subscribed = Data.define(:mailbox, :queued) { include Encodable }
      Send = Data.define(:id, :to, :envelope, :ttl) { include Encodable }
      Receipt = Data.define(:id, :status, :expires_at) { include Encodable }
      Message = Data.define(:seq, :to, :envelope, :queued_at) { include Encodable }
      Ack = Data.define(:seq) { include Encodable }
      Error = Data.define(:code, :ref, :detail) { include Encodable }

      TYPES = {
        "challenge" => Challenge,
        "subscribe" => Subscribe,
        "subscribed" => Subscribed,
        "send" => Send,
        "receipt" => Receipt,
        "message" => Message,
        "ack" => Ack,
        "error" => Error
      }.freeze

      module_function

      def type_of(klass)
        TYPES.key(klass)
      end

      def decode(text)
        document = parse(text)
        raise UnknownFrame, "unsupported version" unless document["v"] == VERSION

        build(document)
      end

      def parse(text)
        JSON.parse(text)
      rescue JSON::ParserError
        raise UnknownFrame, "malformed frame"
      end

      def build(document)
        klass = TYPES.fetch(document["t"]) { raise UnknownFrame, "unknown type #{document["t"].inspect}" }
        klass.new(**document.except("v", "t").transform_keys(&:to_sym))
      rescue ArgumentError
        raise UnknownFrame, "missing fields for #{document["t"].inspect}"
      end
    end
  end
end
