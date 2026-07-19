# frozen_string_literal: true

require "uri"

module Pando
  # RelaysUi manages relay configuration in-app: a two-step add modal (URL,
  # then an optional access token) and a switch picker. Adding or switching
  # activates the relay and reconnects the Hub through it.
  module RelaysUi
    def self.included(base)
      base.command "Add relay", :open_add_relay
      base.command "Switch relay", :open_relay_list
    end

    def open_add_relay
      close_command_palette
      session[:add_relay_open] = true
      focus.push_scope([:relay_url_input], origin: :modal)
      show
    end

    # Focus slot: step one of the add-relay modal — the URL.
    def relay_url_input
      @relay_url_input ||= Charming::Components::TextInput.new(
        value: relay_url_state[:value], width: 40, placeholder: "http://host:8787"
      )
    end

    def relay_url_input_submitted(value)
      url = value.strip
      return reject_relay_url unless valid_relay_url?(url)

      session[:new_relay_url] = url
      focus.pop_scope
      focus.push_scope([:relay_token_input], origin: :modal)
      show
    end

    def relay_url_input_cancelled
      close_add_relay
      show
    end

    # Focus slot: step two — the optional token.
    def relay_token_input
      @relay_token_input ||= Charming::Components::TextInput.new(
        value: relay_token_state[:value], width: 40, placeholder: "access token — enter to skip"
      )
    end

    def relay_token_input_submitted(value)
      url = session.delete(:new_relay_url)
      token = value.strip
      relay = RelayConfig.create!(name: URI(url).host, url: url,
        token: token.empty? ? nil : token)
      close_add_relay
      switch_to(relay)
    rescue ActiveRecord::RecordInvalid
      close_add_relay
      show_toast("That relay is already configured", kind: :warn)
      show
    end

    def relay_token_input_cancelled
      close_add_relay
      show
    end

    def open_relay_list
      close_command_palette
      session[:relay_list_open] = true
      focus.push_scope([:relay_list], origin: :modal)
      show
    end

    # Focus slot: the saved-relay picker.
    def relay_list
      @relay_list ||= RelayList.new(relays: RelayConfig.order(:created_at).to_a,
        selected_index: relay_list_state[:index], theme: theme)
    end

    def relay_list_selected(relay)
      close_relay_list
      switch_to(relay)
    end

    def relay_list_cancelled
      close_relay_list
      show
    end

    private

    def switch_to(relay)
      relay.activate!
      reconnect_hub!
      show_toast("Switched to #{relay.display_name}")
      show
    end

    def valid_relay_url?(url)
      uri = URI(url)
      %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end

    def reject_relay_url
      show_toast("Enter a relay URL like http://host:8787", kind: :warn)
      relay_url_state[:value] = ""
      @relay_url_input = nil
      show
    end

    def relays_modal
      return add_relay_url_modal if session[:add_relay_open] && !session[:new_relay_url]
      return add_relay_token_modal if session[:add_relay_open]
      return relay_list_modal if session[:relay_list_open]

      nil
    end

    def add_relay_url_modal
      {title: "Add relay — URL", content: relay_url_input, help: "enter next · esc cancel"}
    end

    def add_relay_token_modal
      {title: "Add relay — token", content: relay_token_input,
       help: "enter save (blank for none) · esc cancel"}
    end

    def relay_list_modal
      {title: "Switch relay", content: relay_list, help: "enter switch · esc close"}
    end

    def close_add_relay
      session[:add_relay_open] = false
      session.delete(:new_relay_url)
      relay_url_state[:value] = ""
      relay_token_state[:value] = ""
      @relay_url_input = nil
      @relay_token_input = nil
      focus.pop_scope
    end

    def close_relay_list
      session[:relay_list_open] = false
      relay_list_state[:index] = 0
      @relay_list = nil
      focus.pop_scope
    end

    def persist_relays_state
      relay_url_state[:value] = relay_url_input.value if session[:add_relay_open] && !session[:new_relay_url]
      relay_token_state[:value] = relay_token_input.value if session[:add_relay_open] && session[:new_relay_url]
      relay_list_state[:index] = relay_list.selected_index if session[:relay_list_open]
    end

    def relay_url_state
      component_state(:relay_url, value: "")
    end

    def relay_token_state
      component_state(:relay_token, value: "")
    end

    def relay_list_state
      component_state(:relay_list, index: 0)
    end
  end
end
