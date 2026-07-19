# frozen_string_literal: true

module Pando
  # ContactCard is a name + signed device bundle received over the wire (inside a
  # contact-request or contact-accept). It quacks like Invite — name, bundle,
  # fingerprint, verified_bundle — so AddContact accepts either source.
  class ContactCard
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
    rescue KeyError, TypeError
      nil
    end
  end
end
