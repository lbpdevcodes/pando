# frozen_string_literal: true

module Pando
  # Attachments move files through the same encrypted channel as text: a
  # manifest (name/mime/size/digest) followed by base64 chunks, reassembled and
  # digest-verified on receipt, with blobs sealed at rest.
  module Attachments
    # Raw bytes per chunk. The wire cost of a chunk is roughly 16/9 of the raw
    # size (base64 in the body, then NaCl box, then base64 again in the
    # envelope JSON), so 128 KiB raw ≈ 234 KiB on the wire — safely under the
    # relay's 256 KiB frame cap. A unit test locks this math against drift.
    CHUNK_BYTES = 128 * 1024

    # 64 chunks ≈ 14.6 MiB of queued envelope bytes — one full attachment fits
    # a recipient's 16 MiB offline mailbox.
    MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024
  end
end
