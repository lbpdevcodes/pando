# frozen_string_literal: true

require "fileutils"

module Pando
  class OnboardingController < ApplicationController
    layout Layouts::OnboardingLayout
    focus_ring :passphrase

    command "Enroll this device", :begin_enrollment
    on_task :enroll_poll, action: :enrollment_polled

    def show
      persist_input
      render :show,
        passphrase: passphrase,
        creating: !Store.keyring_exists?,
        mode: onboarding_state.mode,
        enroll_code: onboarding_state.enroll_code,
        safety_code: onboarding_state.safety_code,
        error: onboarding_state.error,
        palette: command_palette
    end

    # Focus slot: the masked passphrase input.
    def passphrase
      @passphrase ||= Charming::Components::TextInput.new(
        value: passphrase_state[:value], masked: true, width: 40
      )
    end

    def passphrase_submitted(value)
      return show if value.empty?
      return start_enrollment(value) if onboarding_state.mode == "enroll"

      unlock_or_create(value)
    end

    # Enrolling replaces creating a fresh identity — only offered before any
    # keyring exists, so it can never clobber an established account.
    def begin_enrollment
      close_command_palette
      if Store.keyring_exists?
        show_toast("This device already has a profile", kind: :warn)
      else
        onboarding_state.mode = "enroll"
        onboarding_state.error = nil
      end
      show
    end

    def enrollment_polled
      result = event.error? ? :denied : event.value
      case result
      when :denied then enrollment_failed("Enrollment was denied or expired")
      when Hash then complete_enrollment(result)
      else enrollment_failed("Enrollment timed out")
      end
    end

    private

    def unlock_or_create(value)
      keyring = open_keyring(value)
      return show unless keyring

      Store.data_key = keyring.data_key
      session[:identity] = keyring.identity
      passphrase_state[:value] = ""
      DemoSeed.plant if ENV["PANDO_DEMO"]
      navigate_to "/"
    end

    def open_keyring(value)
      if Store.keyring_exists?
        Store::Keyring.open(path: Store.keyring_path, passphrase: value)
      else
        create_keyring(value)
      end
    rescue Store::Keyring::WrongPassphrase
      onboarding_state.error = "Wrong passphrase — try again."
      nil
    end

    def create_keyring(value)
      FileUtils.mkdir_p(Store.root)
      Store::Keyring.create(
        path: Store.keyring_path, passphrase: value,
        identity: Crypto::Identity.generate, params: keyring_params
      )
    end

    # Interactive Argon2id keeps unlock fast at a TUI prompt; the params live in
    # the keyring file, so hardening later only affects new keyrings.
    def keyring_params
      {opslimit: :interactive, memlimit: :interactive}
    end

    # Deposits the offer and (on a threaded host) polls for the grant. Under
    # the inline executor the waiting screen renders but nothing polls — the
    # enrollment flow needs a live app.
    def start_enrollment(value)
      session[:enroll_passphrase] = value
      passphrase_state[:value] = ""
      @passphrase = nil
      offer = Client::Enrollment::Offer.new(rendezvous: rendezvous_client)
      offer.deposit!
      session[:enroll_offer] = offer
      onboarding_state.mode = "enroll_waiting"
      onboarding_state.enroll_code = offer.code
      onboarding_state.safety_code = offer.safety_code
      start_enroll_poll(offer)
      show
    rescue Client::RendezvousClient::Error
      enrollment_failed("Couldn't reach the relay — check your connection")
    end

    def start_enroll_poll(offer)
      return unless application.task_executor.is_a?(Charming::Tasks::ThreadedExecutor)

      run_task(:enroll_poll, timeout: 300) do
        result = :waiting
        while result == :waiting
          sleep 2
          result = offer.poll
        end
        result
      end
    end

    def complete_enrollment(result)
      FileUtils.mkdir_p(Store.root)
      keyring = Store::Keyring.create(
        path: Store.keyring_path, passphrase: session.delete(:enroll_passphrase),
        identity: result[:identity], params: keyring_params
      )
      Store.data_key = keyring.data_key
      session[:identity] = keyring.identity
      my_fingerprint = Crypto::Identity.account_from(keyring.identity).fingerprint
      EnrollmentImport.new(my_fingerprint: my_fingerprint).call(result[:import])
      session[:enroll_offer]&.cleanup
      session.delete(:enroll_offer)
      # The announce goes out once the Hub connects (Connectivity#apply_status).
      session[:announce_pending] = true
      navigate_to "/"
    end

    def enrollment_failed(message)
      onboarding_state.mode = "unlock"
      onboarding_state.error = message
      session.delete(:enroll_offer)
      session.delete(:enroll_passphrase)
      show
    end

    def rendezvous_client
      Client::Enrollment.rendezvous_for(relay_url, token: relay_token)
    end

    def persist_input
      passphrase_state[:value] = passphrase.value
    end

    def passphrase_state
      component_state(:passphrase, value: "")
    end

    def onboarding_state
      state(:onboarding, OnboardingState)
    end
  end
end
