# frozen_string_literal: true

require "json"

module Pando
  module Relay
    # SocketSession is one client's WebSocket lifetime: challenge, subscribe,
    # then a pump of sends, deliveries, and acks. Delivery is ack-gated even when
    # live — an envelope handed to a live session that dies before acking is
    # re-queued on teardown, so a crash between forward and ack loses nothing.
    class SocketSession
      def initialize(connection:, directory:, queue:, registry:, limits:)
        @connection = connection
        @directory = directory
        @queue = queue
        @registry = registry
        @limits = limits
        @pending = {}
        @seq = 0
        @write_mutex = Mutex.new
        @mailbox = nil
      end

      def run
        challenge = Challenge.new
        write(Protocol::Frames::Challenge.new(nonce: challenge.nonce))
        pump(challenge)
      ensure
        teardown
      end

      # Called by the *sender's* session to hand an envelope to this live session.
      # Returns false when this session can no longer be written to.
      def deliver_live(to:, envelope:, expires_at:)
        seq = next_seq
        @pending[seq] = {kind: :live, to: to, envelope: envelope, expires_at: expires_at}
        write(Protocol::Frames::Message.new(seq: seq, to: to, envelope: envelope, queued_at: nil))
        true
      rescue => _error
        false
      end

      private

      attr_reader :connection, :directory, :queue, :registry, :limits

      def pump(challenge)
        while (message = connection.read)
          handle(Protocol::Frames.decode(message.to_str), challenge)
        end
      rescue Protocol::Frames::UnknownFrame
        write(error_frame("bad_frame", nil, "unrecognized frame"))
      rescue EOFError, Errno::ECONNRESET, ::Protocol::WebSocket::ClosedError
        nil # client went away without a close handshake — a normal ending here
      end

      def handle(frame, challenge)
        case frame
        when Protocol::Frames::Subscribe then subscribe(frame, challenge)
        when Protocol::Frames::Send then accept_send(frame)
        when Protocol::Frames::Ack then acknowledge(frame.seq)
        end
      end

      def subscribe(frame, challenge)
        unless authorized?(frame, challenge)
          write(error_frame("unauthorized", frame.mailbox, "mailbox ownership proof failed"))
          return
        end

        @mailbox = frame.mailbox
        registry.register(@mailbox, self)
        drain_backlog
      end

      def authorized?(frame, challenge)
        !challenge.expired?(now: now) && challenge.proof_valid?(
          mailbox: frame.mailbox,
          device_key: frame.device_key.unpack1("m0"),
          sig: frame.sig.unpack1("m0"),
          directory: directory
        )
      end

      def drain_backlog
        backlog = queue.drain(mailbox: @mailbox, now: now)
        write(Protocol::Frames::Subscribed.new(mailbox: @mailbox, queued: backlog.length))
        backlog.each { |row| deliver_queued(row) }
      end

      def deliver_queued(row)
        seq = next_seq
        @pending[seq] = {kind: :queued, row_seq: row.fetch(:seq)}
        write(Protocol::Frames::Message.new(
          seq: seq, to: @mailbox, envelope: JSON.parse(row.fetch(:envelope)), queued_at: nil
        ))
      end

      def accept_send(frame)
        envelope_json = JSON.generate(frame.envelope)
        return write(error_frame("frame_too_large", frame.id, "over #{limits.max_frame_bytes} bytes")) if envelope_json.bytesize > limits.max_frame_bytes

        expires_at = now + effective_ttl(frame.ttl)
        status = forward_or_queue(frame, envelope_json, expires_at)
        write(Protocol::Frames::Receipt.new(id: frame.id, status: status, expires_at: expires_at)) if status
      rescue QueueStore::QueueFull
        write(error_frame("queue_full", frame.id, "recipient mailbox is full"))
      end

      def forward_or_queue(frame, envelope_json, expires_at)
        live = registry.sessions_for(frame.to)
        delivered = live.count { |session| session.deliver_live(to: frame.to, envelope: frame.envelope, expires_at: expires_at) }
        return "delivered" if delivered.positive?

        queue.enqueue(mailbox: frame.to, envelope: envelope_json, expires_at: expires_at)
        "queued"
      end

      def acknowledge(seq)
        entry = @pending.delete(seq)
        queue.ack(seq: entry.fetch(:row_seq)) if entry && entry.fetch(:kind) == :queued
      end

      # Live envelopes handed to this session but never acked go back to the queue;
      # everything queued-but-unacked simply stays queued.
      def teardown
        registry.unregister(@mailbox, self) if @mailbox
        @pending.each_value do |entry|
          next unless entry.fetch(:kind) == :live

          requeue(entry)
        end
      end

      def requeue(entry)
        queue.enqueue(
          mailbox: entry.fetch(:to),
          envelope: JSON.generate(entry.fetch(:envelope)),
          expires_at: entry.fetch(:expires_at)
        )
      rescue QueueStore::QueueFull
        nil
      end

      def effective_ttl(ttl)
        return limits.queue_ttl if ttl.nil? || ttl.to_i <= 0

        [ttl.to_i, limits.queue_ttl].min
      end

      def error_frame(code, ref, detail)
        Protocol::Frames::Error.new(code: code, ref: ref, detail: detail)
      end

      # Writes flush immediately: cross-session deliveries run on the sender's
      # fiber, and the recipient's own fiber (parked in read) would never flush
      # a buffered frame on its behalf.
      def write(frame)
        @write_mutex.synchronize do
          connection.write(frame.encode)
          connection.flush
        end
      end

      def next_seq
        @seq += 1
      end

      def now
        Time.now.to_i
      end
    end
  end
end
