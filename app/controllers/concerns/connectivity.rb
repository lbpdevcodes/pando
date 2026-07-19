# frozen_string_literal: true

module Pando
  # Connectivity owns the client's one persistent relay connection from inside the
  # controller layer. The Hub runs on a background task thread started once after
  # unlock; its status changes and inbound frames arrive as `on_task_progress`
  # events. Because task events dispatch to whatever controller is active, this is
  # mixed into ApplicationController so every screen keeps the connection alive and
  # keeps ingesting — no screen can starve the socket.
  module Connectivity
    def self.included(base)
      base.on_task_progress :connection, action: :handle_connection_event
      base.before_action :ensure_connected
    end

    # Sends a content document to every device of the given bundles through the Hub.
    def deliver_content(content, to_bundles:)
      return unless hub

      Client::Outbox.new(connection: hub, device: hub.device).deliver(content, to_bundles: to_bundles)
    end

    def connection_status
      session[:connection_status] || "connecting"
    end

    # This account's fingerprint, used to form symmetric DM conversation keys so
    # both ends address the same conversation.
    def my_fingerprint
      return nil unless session[:identity]

      @my_fingerprint ||= Crypto::Identity.account_from(session[:identity]).fingerprint
    end

    # Each Hub report is a JSON-safe payload: a status change or an inbound
    # frame. PUBLIC on purpose: the runtime dispatches bound actions with
    # public_send, so every on_task_progress/on_task/timer/key action must be
    # public (spec/controllers/action_visibility_spec.rb enforces this).
    def handle_connection_event
      payload = event.message
      return show if payload.nil?

      case payload["type"]
      when "status" then apply_status(payload)
      when "frame" then ingest(payload["frame"])
      end
      render_default_action
    end

    private

    def ensure_connected
      return unless can_connect?

      session[:connection_started] = true
      session[:hub] = build_hub
      run_task(:connection) { |progress| session[:hub].run(progress) }
    end

    # The Hub is an endless loop, so it can only live on a background thread — under
    # the inline executor (tests, thread-averse hosts) it would block the event loop,
    # so we skip it and the UI simply shows "offline".
    def can_connect?
      Store.unlocked? && session[:identity] && !session[:connection_started] &&
        application.task_executor.is_a?(Charming::Tasks::ThreadedExecutor)
    end

    def build_hub
      seed_relay_from_env
      Client::Hub.new(identity: session[:identity], relay_url: relay_url,
        token: relay_token, discoverable: Setting.get("discoverable") == "1")
    end

    # Tears down the current Hub and connects through the (newly) active relay.
    # The old hub's parting "offline" report may land after the new hub's
    # "online" — a cosmetic flash the next status report corrects.
    def reconnect_hub!
      session[:hub]&.stop!
      session[:hub] = nil
      session[:connection_started] = false
      session[:connection_status] = "connecting"
      ensure_connected
    end

    def hub
      session[:hub]
    end

    # UI-managed relay config wins once one exists; PANDO_RELAY seeds the first
    # row (see build_hub) and remains the fallback before any unlock.
    def relay_url
      RelayConfig.active_relay&.url || ENV.fetch("PANDO_RELAY", "http://127.0.0.1:8787")
    end

    # Tokens are encrypted at rest; before unlock (onboarding) act as if none
    # is configured rather than crashing the screen.
    def relay_token
      RelayConfig.active_relay&.token
    rescue Store::Locked
      nil
    end

    def directory_client
      Client::DirectoryClient.new(relay_url, token: relay_token)
    end

    def seed_relay_from_env
      return if RelayConfig.exists? || ENV["PANDO_RELAY"].to_s.empty?

      url = ENV["PANDO_RELAY"]
      RelayConfig.create!(name: URI(url).host, url: url, active: true)
    end

    # Every transition INTO online — first connect after boot or any reconnect —
    # re-sends messages still pending. Rows persisted by a dead process and
    # frames lost from the Hub's in-memory queue both surface here, because
    # neither ever received the relay receipt that promotes pending to sent.
    def apply_status(payload)
      went_online = payload["value"] == "online" && session[:connection_status] != "online"
      session[:connection_status] = payload["value"]
      return unless went_online

      Redeliver.new(hub: hub).call
      announce_new_device if session[:announce_pending]
    end

    # A freshly enrolled device introduces itself to every contact's devices
    # and its own siblings on first connect, so their fan-out includes us.
    def announce_new_device
      session.delete(:announce_pending)
      bundles = Contact.pluck(:fingerprint)
        .flat_map { |fingerprint| ContactDevice.bundles_for(fingerprint) }
      bundles += ContactDevice.bundles_for(my_fingerprint)
        .reject { |bundle| bundle.mailbox == hub.device.mailbox }
      return if bundles.empty?

      deliver_content(DeviceAnnounce.build(hub.bundle, my_fingerprint: my_fingerprint),
        to_bundles: bundles)
    end

    def ingest(frame)
      notify_ingest(Ingestor.new(hub: hub).ingest_frame(frame))
    end

    # Human copy for the relay's error codes — every code the relay can send
    # has a sentence, never a silent drop.
    RELAY_ERROR_COPY = {
      "queue_full" => "Their relay inbox is full — message not delivered, retry later (ctrl+p → Retry failed messages)",
      "frame_too_large" => "The relay rejected a frame as too large — try a smaller attachment",
      "unauthorized" => "The relay rejected our credentials — check the relay token (ctrl+p → Switch relay)",
      "bad_frame" => "The relay didn't understand a frame — client/relay version mismatch?"
    }.freeze

    def notify_ingest(result)
      kind, detail = result
      case kind
      when :contact_request then show_toast("New contact request — ctrl+p → Contact requests", kind: :info)
      when :contact_accepted then show_toast("Contact request accepted", kind: :info)
      when :key_changed then show_toast("A contact's key has changed — verify before trusting", kind: :error)
      when :relay_error
        show_toast(RELAY_ERROR_COPY.fetch(detail, "Relay error: #{detail}"), kind: :error)
      when :room_removed then show_toast("You were removed from a room", kind: :warn)
      when :typing then note_typing(detail)
      end
    end

    # Ephemeral typing hints: a per-conversation timestamp the header reads;
    # the typing_expiry timer clears stale entries.
    def note_typing(conversation_key)
      (session[:typing] ||= {})[conversation_key] = Time.now.to_f
    end

    def typing_in?(conversation_key)
      stamp = session[:typing]&.fetch(conversation_key, nil)
      !!stamp && Time.now.to_f - stamp < 6
    end
  end
end
