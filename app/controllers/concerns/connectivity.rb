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
      Client::Hub.new(identity: session[:identity], relay_url: relay_url,
        discoverable: Setting.get("discoverable") == "1")
    end

    def hub
      session[:hub]
    end

    def relay_url
      ENV.fetch("PANDO_RELAY", "http://127.0.0.1:8787")
    end

    # Each Hub report is a JSON-safe payload: a status change or an inbound frame.
    def handle_connection_event
      payload = event.message
      return show if payload.nil?

      case payload["type"]
      when "status" then apply_status(payload)
      when "frame" then ingest(payload["frame"])
      end
      render_default_action
    end

    # Every transition INTO online — first connect after boot or any reconnect —
    # re-sends messages still pending. Rows persisted by a dead process and
    # frames lost from the Hub's in-memory queue both surface here, because
    # neither ever received the relay receipt that promotes pending to sent.
    def apply_status(payload)
      went_online = payload["value"] == "online" && session[:connection_status] != "online"
      session[:connection_status] = payload["value"]
      Redeliver.new(hub: hub).call if went_online
    end

    def ingest(frame)
      notify_ingest(Ingestor.new(hub: hub).ingest_frame(frame))
    end

    def notify_ingest(result)
      case result&.first
      when :contact_request then show_toast("New contact request — ctrl+p → Contact requests", kind: :info)
      when :contact_accepted then show_toast("Contact request accepted", kind: :info)
      when :key_changed then show_toast("A contact's key has changed — verify before trusting", kind: :error)
      when :failed then show_toast("A message was rejected by the relay — ctrl+p → Retry failed messages", kind: :error)
      when :room_removed then show_toast("You were removed from a room", kind: :warn)
      end
    end
  end
end
