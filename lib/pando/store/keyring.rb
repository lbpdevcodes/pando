# frozen_string_literal: true

require "json"

module Pando
  module Store
    # Keyring is the profile's root secret file. A passphrase-derived master key
    # (Argon2id) wraps a random 32-byte data key; the data key seals the identity
    # document and everything else at rest. Changing the passphrase re-wraps only
    # the data key — no stored data is re-encrypted.
    class Keyring
      WrongPassphrase = Class.new(StandardError)

      DEFAULT_PARAMS = {opslimit: :moderate, memlimit: :moderate}.freeze

      def self.create(path:, passphrase:, identity:, params: DEFAULT_PARAMS)
        new(path: path, data_key: RbNaCl::Random.random_bytes(32), identity: identity, params: params)
          .tap { |keyring| keyring.rekey(passphrase: passphrase) }
      end

      def self.open(path:, passphrase:)
        document = JSON.parse(File.binread(path))
        params = document.fetch("kdf").slice("opslimit", "memlimit").transform_values(&:to_sym)
        data_key = unwrap_data_key(document, passphrase)
        identity = JSON.parse(SecretEnvelope.open(document.fetch("identity"), key: data_key))
        new(path: path, data_key: data_key, identity: identity, params: params.transform_keys(&:to_sym))
      end

      def self.unwrap_data_key(document, passphrase)
        kdf = document.fetch("kdf")
        master = derive(passphrase, kdf.fetch("salt").unpack1("m0"), kdf)
        SecretEnvelope.open(document.fetch("data_key"), key: master)
      rescue RbNaCl::CryptoError
        raise WrongPassphrase, "wrong passphrase for keyring"
      end

      def self.derive(passphrase, salt, params)
        RbNaCl::PasswordHash.argon2id(
          passphrase, salt,
          params.fetch("opslimit").to_sym, params.fetch("memlimit").to_sym,
          RbNaCl::SecretBox.key_bytes
        )
      end

      attr_reader :data_key, :identity

      def initialize(path:, data_key:, identity:, params:)
        @path = path
        @data_key = data_key
        @identity = identity
        @params = params
      end

      def rekey(passphrase:)
        salt = RbNaCl::Random.random_bytes(RbNaCl::PasswordHash::Argon2::SALTBYTES)
        master = self.class.derive(passphrase, salt, stringified_params)
        write(document(salt, master))
      end

      private

      attr_reader :path, :params

      def document(salt, master)
        {
          "v" => 1,
          "kdf" => stringified_params.merge("salt" => [salt].pack("m0")),
          "data_key" => SecretEnvelope.seal(data_key, key: master),
          "identity" => SecretEnvelope.seal(JSON.generate(identity), key: data_key)
        }
      end

      def stringified_params
        params.to_h { |key, value| [key.to_s, value.to_s] }
      end

      def write(document)
        File.write(path, JSON.pretty_generate(document))
        File.chmod(0o600, path)
      end
    end
  end
end
