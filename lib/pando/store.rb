# frozen_string_literal: true

module Pando
  # Store is the profile's at-rest world: where the keyring lives and, once a
  # passphrase unlocks it, the process-wide data key that encrypted database
  # columns and blobs seal under. Nothing sensitive can be read or written while
  # locked — EncryptedType raises Locked instead of touching plaintext.
  module Store
    Locked = Class.new(StandardError)

    class << self
      attr_writer :data_key

      def data_key
        @data_key or raise Locked, "profile is locked — unlock the keyring first"
      end

      def unlocked?
        !@data_key.nil?
      end

      def lock!
        @data_key = nil
      end

      def root
        ENV.fetch("PANDO_ROOT") { File.expand_path("~/.pando") }
      end

      def keyring_path
        File.join(root, "keyring.json")
      end

      def keyring_exists?
        File.exist?(keyring_path)
      end
    end
  end
end
