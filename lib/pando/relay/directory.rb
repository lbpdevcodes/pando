# frozen_string_literal: true

require "json"
require "sqlite3"

module Pando
  module Relay
    # Directory stores published device bundles: the proof of who owns which mailbox
    # (always available for routing and subscribe checks) and, when the account opts
    # in, a discovery listing by fingerprint. Only bundles whose account signature
    # verifies are accepted, so the directory can never assert an ownership the
    # account didn't sign.
    class Directory
      InvalidBundle = Class.new(StandardError)

      def initialize(db_path)
        @db = SQLite3::Database.new(db_path)
        @db.busy_timeout = 1_000
        @db.execute("PRAGMA journal_mode = WAL")
        migrate
      end

      def publish(bundle_hash, discoverable: false)
        bundle = verified_bundle(bundle_hash)
        db.execute(
          "INSERT INTO directory_bundles (mailbox, fingerprint, bundle, discoverable) VALUES (?, ?, ?, ?)
           ON CONFLICT (mailbox) DO UPDATE SET fingerprint = excluded.fingerprint,
             bundle = excluded.bundle, discoverable = excluded.discoverable",
          [bundle.mailbox, bundle.fingerprint, JSON.generate(bundle_hash), discoverable ? 1 : 0]
        )
      end

      def bundle_for_mailbox(mailbox)
        row = db.get_first_value("SELECT bundle FROM directory_bundles WHERE mailbox = ?", [mailbox])
        row && JSON.parse(row)
      end

      def discover(fingerprint:)
        db.execute(
          "SELECT bundle FROM directory_bundles WHERE fingerprint = ? AND discoverable = 1 ORDER BY mailbox",
          [fingerprint]
        ).map { |(bundle)| JSON.parse(bundle) }
      end

      private

      attr_reader :db

      def verified_bundle(bundle_hash)
        bundle = Crypto::DeviceBundle.from_h(bundle_hash)
        raise InvalidBundle, "bundle signature does not verify" unless bundle.verified?

        bundle
      rescue KeyError
        raise InvalidBundle, "bundle is missing fields"
      end

      def migrate
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS directory_bundles (
            mailbox TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL,
            bundle TEXT NOT NULL,
            discoverable INTEGER NOT NULL DEFAULT 0
          )
        SQL
        db.execute("CREATE INDEX IF NOT EXISTS idx_directory_fingerprint ON directory_bundles (fingerprint)")
      end
    end
  end
end
