# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module Pando
  module Protocol
    # Content is the document inside an envelope's ciphertext — the one schema every
    # feature speaks, direct messages and rooms alike. A conversation id addresses it
    # ("dm:<fp>:<fp>" or "room:<uuid>"); the kind says what the body means (text,
    # receipt, typing, attachment-manifest, room-update, ...).
    class Content
      Malformed = Class.new(StandardError)

      def self.text(body, conversation:, ttl: 0)
        new(kind: "text", conversation: conversation, body: body, ttl: ttl)
      end

      def self.dm_conversation(fingerprint_a, fingerprint_b)
        "dm:#{[fingerprint_a, fingerprint_b].sort.join(":")}"
      end

      def self.from_json(json)
        document = JSON.parse(json)
        new(kind: document.fetch("kind"), conversation: document.fetch("conversation"),
          body: document.fetch("body"), id: document.fetch("id"),
          sent_at: document.fetch("sent_at"), ttl: document.fetch("ttl"))
      rescue JSON::ParserError, KeyError
        raise Malformed, "not a content document"
      end

      attr_reader :kind, :conversation, :body, :id, :sent_at, :ttl

      def initialize(kind:, conversation:, body:, id: SecureRandom.uuid, sent_at: Time.now.utc.iso8601, ttl: 0)
        @kind = kind
        @conversation = conversation
        @body = body
        @id = id
        @sent_at = sent_at
        @ttl = ttl
      end

      def to_json
        JSON.generate({"v" => 1, "kind" => kind, "conversation" => conversation,
                       "id" => id, "sent_at" => sent_at, "ttl" => ttl, "body" => body})
      end
    end
  end
end
