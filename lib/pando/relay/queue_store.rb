# frozen_string_literal: true

require "sqlite3"

module Pando
  module Relay
    # QueueStore holds envelopes for offline mailboxes in SQLite (WAL mode, so the
    # relay's fibers can read while one writes). Envelopes stay queued until acked
    # by the recipient or expired; per-mailbox caps bound what one mailbox can hold.
    class QueueStore
      QueueFull = Class.new(StandardError)

      def initialize(db_path, limits: Protocol::Limits.default)
        @db = SQLite3::Database.new(db_path)
        @db.busy_timeout = 1_000
        @db.execute("PRAGMA journal_mode = WAL")
        @limits = limits
        migrate
      end

      def enqueue(mailbox:, envelope:, expires_at:)
        ensure_capacity(mailbox, envelope.bytesize)
        db.execute(
          "INSERT INTO queued_messages (mailbox, envelope, expires_at, bytes) VALUES (?, ?, ?, ?)",
          [mailbox, envelope, expires_at, envelope.bytesize]
        )
        db.last_insert_row_id
      end

      def drain(mailbox:, now:)
        rows = db.execute(
          "SELECT seq, envelope, expires_at FROM queued_messages WHERE mailbox = ? AND expires_at > ? ORDER BY seq",
          [mailbox, now]
        )
        rows.map { |seq, envelope, expires_at| {seq: seq, envelope: envelope, expires_at: expires_at} }
      end

      def ack(seq:)
        db.execute("DELETE FROM queued_messages WHERE seq = ?", [seq])
      end

      def sweep(now:)
        db.execute("DELETE FROM queued_messages WHERE expires_at <= ?", [now])
        db.changes
      end

      private

      attr_reader :db, :limits

      def ensure_capacity(mailbox, incoming_bytes)
        count, bytes = db.get_first_row(
          "SELECT COUNT(*), COALESCE(SUM(bytes), 0) FROM queued_messages WHERE mailbox = ?", [mailbox]
        )
        raise QueueFull, "mailbox #{mailbox} at message cap" if count >= limits.max_queued_messages
        raise QueueFull, "mailbox #{mailbox} at byte cap" if bytes + incoming_bytes > limits.max_queued_bytes
      end

      def migrate
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS queued_messages (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            mailbox TEXT NOT NULL,
            envelope TEXT NOT NULL,
            expires_at INTEGER NOT NULL,
            bytes INTEGER NOT NULL
          )
        SQL
        db.execute("CREATE INDEX IF NOT EXISTS idx_queued_mailbox ON queued_messages (mailbox)")
      end
    end
  end
end
