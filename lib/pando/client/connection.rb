# frozen_string_literal: true

require "socket"
require "uri"
require "websocket/driver"

module Pando
  module Client
    # Connection is a blocking WebSocket client for one relay: it performs the
    # challenge/subscribe handshake and then reads and writes protocol frames.
    # Deliberately thread-simple — the TUI runs one Connection inside a background
    # task thread; the reconnect/backoff loop lives above it, not in it.
    class Connection
      ConnectionClosed = Class.new(StandardError)
      SubscribeRejected = Class.new(StandardError)
      WaitTimeout = Class.new(StandardError)

      READ_CHUNK = 4096

      # Connects, authenticates the device's mailbox, and returns a ready connection.
      def self.open(url, device:, timeout: 5)
        new(url, timeout: timeout).tap { |connection| connection.subscribe!(device) }
      end

      attr_reader :url, :subscribed

      def initialize(url, timeout: 5)
        @url = url
        @timeout = timeout
        @frames = []
        @open = false
        uri = URI(url)
        @socket = TCPSocket.new(uri.host, uri.port)
        @driver = WebSocket::Driver.client(self)
        wire_driver
        @driver.start
        pump until @open
      end

      # websocket-driver's socket interface: it calls this to emit handshake/frame bytes.
      def write(data)
        @socket.write(data)
      end

      def subscribe!(device)
        challenge = next_frame
        @driver.text(subscribe_frame(device, challenge.nonce).encode)
        reply = next_frame
        raise SubscribeRejected, "#{reply.code}: #{reply.detail}" if reply.is_a?(Protocol::Frames::Error)

        @subscribed = reply
      end

      def send_frame(frame)
        @driver.text(frame.encode)
      end

      def send_envelope(id:, to:, envelope:, ttl:)
        send_frame(Protocol::Frames::Send.new(id: id, to: to, envelope: envelope, ttl: ttl))
      end

      def ack(seq)
        send_frame(Protocol::Frames::Ack.new(seq: seq))
      end

      # Blocks until the next frame arrives (or WaitTimeout).
      def next_frame(timeout: @timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        pump_until(deadline) while @frames.empty?
        @frames.shift
      end

      # Non-blocking-ish poll: the next frame within *timeout*, or nil.
      def poll_frame(timeout: 0.05)
        next_frame(timeout: timeout)
      rescue WaitTimeout
        nil
      end

      def close
        @driver.close
        @socket.close
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        nil
      end

      private

      def wire_driver
        @driver.on(:open) { @open = true }
        @driver.on(:message) { |event| @frames << Protocol::Frames.decode(event.data) }
        @driver.on(:close) { @closed = true }
      end

      def subscribe_frame(device, nonce)
        sig = Protocol::SubscribeProof.sign(device: device, nonce: nonce, mailbox: device.mailbox)
        Protocol::Frames::Subscribe.new(
          mailbox: device.mailbox,
          device_key: [device.signing_public_key].pack("m0"),
          sig: [sig].pack("m0")
        )
      end

      def pump_until(deadline)
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise WaitTimeout, "no frame within timeout" if remaining <= 0

        pump(remaining)
      end

      def pump(wait = nil)
        raise ConnectionClosed, "relay closed the connection" if @closed
        return unless @socket.wait_readable(wait)

        @driver.parse(@socket.readpartial(READ_CHUNK))
      rescue EOFError, Errno::ECONNRESET
        @closed = true
        raise ConnectionClosed, "relay closed the connection"
      end
    end
  end
end
