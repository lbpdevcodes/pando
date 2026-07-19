# frozen_string_literal: true

require "uri"

module Pando
  module Client
    # Hub is the client's connection lifecycle, built to live inside one background
    # task thread: publish the device bundle, connect and subscribe, then pump —
    # draining a thread-safe outgoing queue and surfacing every inbound frame and
    # status change as a progress report to the UI thread. Reconnects with jittered
    # backoff; stop! ends the loop from any thread.
    #
    # It quacks like Connection for Outbox/Inbox (send_envelope/ack), so the same
    # send path works headless and in the TUI.
    class Hub
      POLL_INTERVAL = 0.1

      attr_reader :account, :device

      def initialize(identity:, relay_url:, directory: nil, backoff: Backoff.new,
        discoverable: false, token: nil)
        @account = Crypto::Identity.account_from(identity)
        @device = Crypto::Identity.device_from(identity)
        @relay_url = relay_url
        @token = token
        @directory = directory || DirectoryClient.new(relay_url, token: token)
        @backoff = backoff
        @discoverable = discoverable
        @republish = false
        @outgoing = Thread::Queue.new
        @stop = false
        @seq = 0
      end

      # Toggling discoverability republishes from inside the hub thread on the
      # next pump tick, keeping HTTP off the caller's (UI) thread.
      def discoverable=(flag)
        @discoverable = flag
        @republish = true
      end

      def bundle
        @bundle ||= Crypto::DeviceBundle.issue(device: device, account: account)
      end

      def invite_code(name:)
        Invite.encode(bundle: bundle.to_h, name: name)
      end

      def send_envelope(id:, to:, envelope:, ttl:)
        @outgoing << Protocol::Frames::Send.new(id: id, to: to, envelope: envelope, ttl: ttl)
      end

      def ack(seq)
        @outgoing << Protocol::Frames::Ack.new(seq: seq)
      end

      def stop!
        @stop = true
      end

      def run(progress)
        attempt(progress) until @stop
      ensure
        report(progress, "type" => "status", "value" => "offline")
      end

      private

      attr_reader :relay_url, :directory, :backoff

      def attempt(progress)
        connection = nil
        directory.publish(bundle.to_h, discoverable: @discoverable)
        connection = Connection.open(ws_url, device: device, headers: auth_headers)
        backoff.reset
        report(progress, "type" => "status", "value" => "online", "queued" => connection.subscribed.queued)
        pump(connection, progress)
      rescue Connection::ConnectionClosed, Connection::SubscribeRejected, Connection::WaitTimeout,
        DirectoryClient::Error, SystemCallError, SocketError, IOError => error
        report(progress, "type" => "status", "value" => "reconnecting", "detail" => error.class.name)
        interruptible_sleep(backoff.next_delay)
      ensure
        connection&.close
      end

      def pump(connection, progress)
        until @stop
          republish_if_requested
          drain_outgoing(connection)
          frame = connection.poll_frame(timeout: POLL_INTERVAL)
          report(progress, "type" => "frame", "frame" => frame) if frame
        end
      end

      # A failed republish must not tear down a healthy connection — the flag
      # stays set and the next tick retries.
      def republish_if_requested
        return unless @republish

        directory.publish(bundle.to_h, discoverable: @discoverable)
        @republish = false
      rescue DirectoryClient::Error, SystemCallError, SocketError, IOError
        nil
      end

      def drain_outgoing(connection)
        while (frame = pop_outgoing)
          connection.send_frame(frame)
        end
      end

      def pop_outgoing
        @outgoing.pop(true)
      rescue ThreadError
        nil
      end

      def interruptible_sleep(delay)
        (delay / POLL_INTERVAL).ceil.times do
          break if @stop

          sleep(POLL_INTERVAL)
        end
      end

      def report(progress, payload)
        progress.report(@seq += 1, message: payload)
      end

      def ws_url
        uri = URI(relay_url)
        "ws://#{uri.host}:#{uri.port}/v1/ws"
      end

      def auth_headers
        @token ? {"x-pando-relay-token" => @token} : {}
      end
    end
  end
end
