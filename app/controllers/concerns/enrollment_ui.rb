# frozen_string_literal: true

module Pando
  # EnrollmentUi is the approving side of adding a device: enter the code shown
  # on the new device, compare safety codes, approve (sealing the account seed
  # plus a bootstrap export to the offered key) or deny (deleting the slot).
  # The rendezvous HTTP calls are one-shot with short timeouts and run inline —
  # a worst-case 5s stall beats threading state through an approval this
  # security-sensitive.
  module EnrollmentUi
    def self.included(base)
      base.command "Enroll a device", :open_enroll_device

      base.slot(:enroll_code_input) { TextInput.new(width: 12, placeholder: "6-digit code") }
      base.slot(:enroll_confirm) { EnrollConfirm.new(safety_code: nil, mailbox: nil, theme: theme) }

      base.on_submit :enroll_code_input, :enroll_code_input_submitted
      base.on_cancel :enroll_code_input, :enroll_code_input_cancelled
      base.on_select :enroll_confirm, :enroll_confirm_selected
      base.on_cancel :enroll_confirm, :enroll_confirm_cancelled
    end

    def open_enroll_device
      dismiss_command_palette
      session[:enroll_code_open] = true
      focus.push_scope([:enroll_code_input], origin: :modal)
      show
    end

    def enroll_code_input_submitted(value)
      code = value.strip
      return reject_enroll_code unless code.match?(/\A\d{6}\z/)

      offer = granter.fetch_offer(code)
      return no_offer_found unless offer

      close_enroll_code
      session[:enroll_offer_payload] = offer
      session[:enroll_offer_code] = code
      enroll_confirm.configure(safety_code: granter.safety_code(offer), mailbox: offer["mailbox"])
      session[:enroll_confirm_open] = true
      focus.push_scope([:enroll_confirm], origin: :modal)
      show
    end

    def enroll_code_input_cancelled
      close_enroll_code
      show
    end

    def enroll_confirm_selected(_value)
      offer = session[:enroll_offer_payload]
      code = session[:enroll_offer_code]
      export = EnrollmentExport.build(my_fingerprint: my_fingerprint)
      granter.approve!(offer, code: code, contacts: export[:contacts],
        conversations: export[:conversations], extra_own_devices: export[:own_devices])
      record_enrolled_device(offer)
      close_enroll_confirm
      show_toast("Device approved — it will announce itself shortly")
      show
    rescue Client::RendezvousClient::Error
      close_enroll_confirm
      show_toast("Couldn't deliver the grant — try again", kind: :error)
      show
    end

    def enroll_confirm_cancelled
      granter.deny!(session[:enroll_offer_code])
      close_enroll_confirm
      show_toast("Enrollment denied", kind: :info)
      show
    rescue Client::RendezvousClient::Error
      close_enroll_confirm
      show
    end

    private

    # Resolve the sender before its announce arrives: the row has no bundle
    # yet, so it can't be sealed to, but inbound frames attribute correctly.
    def record_enrolled_device(offer)
      ContactDevice.find_or_create_by!(mailbox: offer["mailbox"]) do |device|
        device.fingerprint = my_fingerprint
        device.box_key = offer["box"]
      end
    end

    def granter
      Client::Enrollment::Grant.new(identity: session[:identity],
        rendezvous: Client::Enrollment.rendezvous_for(relay_url, token: relay_token))
    end

    def reject_enroll_code
      show_toast("Enter the 6-digit code from the new device", kind: :warn)
      enroll_code_input.clear!
      show
    end

    def no_offer_found
      show_toast("No enrollment waiting on that code", kind: :warn)
      enroll_code_input.clear!
      show
    end

    def enrollment_modal
      if session[:enroll_code_open]
        {title: "Enroll a device", content: enroll_code_input, help: "enter next · esc cancel"}
      elsif session[:enroll_confirm_open]
        {title: "Approve this device?", content: enroll_confirm, help: "y approve · n deny"}
      end
    end

    # Clears the memoized input so the next open starts empty.
    def close_enroll_code
      session[:enroll_code_open] = false
      enroll_code_input.clear!
      focus.pop_scope
    end

    def close_enroll_confirm
      session[:enroll_confirm_open] = false
      session.delete(:enroll_offer_payload)
      session.delete(:enroll_offer_code)
      focus.pop_scope
    end
  end
end
