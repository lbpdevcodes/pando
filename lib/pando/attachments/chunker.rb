# frozen_string_literal: true

module Pando
  module Attachments
    # Chunker splits raw bytes into indexed CHUNK_BYTES slices and back.
    module Chunker
      module_function

      def each_chunk(bytes)
        return enum_for(:each_chunk, bytes) unless block_given?

        count(bytes.bytesize).times do |index|
          yield [index, bytes.byteslice(index * CHUNK_BYTES, CHUNK_BYTES)]
        end
      end

      def count(size)
        (size.to_f / CHUNK_BYTES).ceil
      end
    end
  end
end
