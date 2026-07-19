# frozen_string_literal: true

module Pando
  # EnrollConfirm is the approver's decision card: the safety code recomputed
  # from the offered keys, and a y/n choice. Approving hands the account seed
  # to whoever presented these keys — the safety-code comparison is the whole
  # defense against a raced rendezvous code, hence the loud framing.
  class EnrollConfirm < Charming::Component
    def initialize(safety_code:, mailbox:, theme: nil)
      super(theme: theme)
      @safety_code = safety_code
      @mailbox = mailbox
    end

    def render
      column(
        text("A device is asking to join your account.", style: theme.title),
        text("Safety code  #{@safety_code}", style: theme.info),
        text("Mailbox      #{@mailbox}", style: theme.muted),
        text(""),
        text("Approve ONLY if the safety code matches the new device's screen —", style: theme.warn),
        text("approving hands this account's identity to that device.", style: theme.warn)
      )
    end

    def handle_key(event)
      case Charming.key_of(event)
      when :y then [:selected, :approve]
      when :n, :escape then :cancelled
      end
    end
  end
end
