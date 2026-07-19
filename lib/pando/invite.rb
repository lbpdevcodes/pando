# frozen_string_literal: true

require "json"

module Pando
  # Invite is the shareable contact code: URL-safe base64 of a JSON document
  # carrying a display name and a signed device bundle. It contains no secrets —
  # trust comes from comparing fingerprints out-of-band — but a code whose bundle
  # signature fails is rejected outright.
  class Invite
    Malformed = Class.new(StandardError)

    def self.encode(bundle:, name:)
      [JSON.generate({"v" => 1, "name" => name, "bundle" => bundle})].pack("m0").tr("+/", "-_").delete("=")
    end

    def self.decode(code)
      document = parse(code)
      invite = new(name: document.fetch("name"), bundle: document.fetch("bundle"))
      raise Malformed, "invite bundle does not verify" unless invite.verified_bundle

      invite
    end

    def self.parse(code)
      padded = code.tr("-_", "+/") + "=" * (-code.length % 4)
      JSON.parse(padded.unpack1("m0") || "")
    rescue JSON::ParserError, KeyError, ArgumentError
      raise Malformed, "not an invite code"
    end

    attr_reader :name, :bundle

    def initialize(name:, bundle:)
      @name = name
      @bundle = bundle
    end

    def fingerprint
      verified_bundle&.fingerprint
    end

    def verified_bundle
      candidate = Crypto::DeviceBundle.from_h(bundle)
      candidate.verified? ? candidate : nil
    rescue KeyError
      nil
    end
  end
end
