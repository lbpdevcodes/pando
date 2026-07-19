# frozen_string_literal: true

require "fileutils"

module Pando
  class OnboardingController < ApplicationController
    layout Layouts::OnboardingLayout
    focus_ring :passphrase

    def show
      persist_input
      render :show,
        passphrase: passphrase,
        creating: !Store.keyring_exists?,
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

      unlock_or_create(value)
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
