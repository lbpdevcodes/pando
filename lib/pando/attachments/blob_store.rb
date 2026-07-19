# frozen_string_literal: true

require "fileutils"
require "json"

module Pando
  module Attachments
    # BlobStore keeps attachment bytes sealed on disk under the profile root:
    # complete blobs in attachments/, in-flight chunks in attachments/partial/.
    # A partial file's existence doubles as chunk dedup and survives restarts;
    # everything is SecretEnvelope ciphertext under the profile data key.
    class BlobStore
      def write(attachment_id, bytes)
        write_sealed(blob_path(attachment_id), bytes)
      end

      def read(attachment_id)
        read_sealed(blob_path(attachment_id))
      end

      def blob_path(attachment_id)
        File.join(root, "#{attachment_id}.blob")
      end

      def write_partial(attachment_id, index, bytes)
        path = partial_path(attachment_id, index)
        return if File.exist?(path)

        write_sealed(path, bytes)
      end

      def partial_count(attachment_id)
        Dir.glob(File.join(partial_dir(attachment_id), "*.chunk")).length
      end

      # All chunks in index order, or nil while any are still missing.
      def read_partials(attachment_id, total:)
        (0...total).map do |index|
          path = partial_path(attachment_id, index)
          return nil unless File.exist?(path)

          read_sealed(path)
        end
      end

      def purge_partials(attachment_id)
        FileUtils.rm_rf(partial_dir(attachment_id))
      end

      def delete(attachment_id)
        FileUtils.rm_f(blob_path(attachment_id))
      end

      private

      def write_sealed(path, bytes)
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        File.write(path, JSON.generate(Store::SecretEnvelope.seal(bytes, key: Store.data_key)))
        File.chmod(0o600, path)
      end

      def read_sealed(path)
        Store::SecretEnvelope.open(JSON.parse(File.read(path)), key: Store.data_key)
      end

      def partial_path(attachment_id, index)
        File.join(partial_dir(attachment_id), "#{index}.chunk")
      end

      def partial_dir(attachment_id)
        File.join(root, "partial", attachment_id)
      end

      def root
        File.join(Store.root, "attachments")
      end
    end
  end
end
