# frozen_string_literal: true

module Pando
  # VerifyPanel is the out-of-band comparison card: both fingerprints chunked
  # for reading aloud, the current trust level, and enter-to-verify. Verifying
  # re-pins whatever bundle is currently stored — exactly the Trust#verify
  # semantics of trusting the observed key.
  class VerifyPanel < Charming::Component
    def initialize(contact:, my_fingerprint:, theme: nil)
      super(theme: theme)
      @contact = contact
      @my_fingerprint = my_fingerprint
    end

    def render
      column(
        text("Their fingerprint   #{chunk(contact.fingerprint)}", style: theme.title),
        text("Your fingerprint    #{chunk(my_fingerprint)}", style: theme.title),
        text(""),
        text("Trust level: #{contact.trust_level}", style: trust_style),
        text("Compare fingerprints out-of-band before verifying.", style: theme.muted)
      )
    end

    def handle_key(event)
      case Charming.key_of(event)
      when :enter then [:selected, :verify]
      when :escape then :cancelled
      end
    end

    private

    attr_reader :contact, :my_fingerprint

    def chunk(fingerprint)
      fingerprint.to_s.scan(/.{4}/).join(" ")
    end

    def trust_style
      (contact.trust_level == "key_changed") ? theme.warn : theme.info
    end
  end
end
