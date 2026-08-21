# frozen_string_literal: true

module Pando
  # VerificationUi is the trust surface on the chat screen: the verify modal for
  # the active DM's contact, and the alert text shown while a contact's key has
  # changed. Verification is explicit — only this modal moves a contact to
  # verified, so a key_changed banner holds until the user re-verifies here.
  module VerificationUi
    def self.included(base)
      base.command "Verify contact", :open_verify

      base.slot(:verify_panel) { VerifyPanel.new(contact: nil, my_fingerprint: my_fingerprint, theme: theme) }

      base.on_select :verify_panel, :verify_panel_selected
      base.on_cancel :verify_panel, :verify_panel_cancelled
    end

    def open_verify
      dismiss_command_palette
      return no_contact_to_verify unless verifiable_contact

      verify_panel.contact = verifiable_contact
      session[:verify_open] = true
      focus.push_scope([:verify_panel], origin: :modal)
      show
    end

    def verify_panel_selected(_value)
      contact = verifiable_contact
      contact.update!(trust_level: "verified")
      close_verify
      show_toast("Verified #{contact.display_name}")
      show
    end

    def verify_panel_cancelled
      close_verify
      show
    end

    private

    def no_contact_to_verify
      show_toast("Open a DM with a contact to verify them", kind: :warn)
      show
    end

    def verifiable_contact
      active_conversation&.contacts&.first
    end

    def verification_modal
      return nil unless session[:verify_open]

      {title: "Verify #{verifiable_contact&.display_name}", content: verify_panel,
       help: "enter mark verified · esc cancel"}
    end

    def key_change_alert
      contact = verifiable_contact
      return nil unless contact&.trust_level == "key_changed"

      "⚠ #{contact.display_name}'s key has changed — verify before trusting new messages"
    end

    def close_verify
      session[:verify_open] = false
      focus.pop_scope
    end
  end
end
