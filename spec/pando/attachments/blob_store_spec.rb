# frozen_string_literal: true

require "tmpdir"
require "securerandom"

RSpec.describe Pando::Attachments::BlobStore do
  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  let(:store) { described_class.new }
  let(:attachment_id) { SecureRandom.uuid }

  it "round-trips a blob through sealed storage" do
    bytes = SecureRandom.bytes(1024)

    store.write(attachment_id, bytes)

    expect(store.read(attachment_id)).to eq(bytes)
  end

  it "stores only ciphertext on disk" do
    store.write(attachment_id, "very secret image bytes")

    on_disk = File.binread(store.blob_path(attachment_id))
    expect(on_disk).not_to include("very secret image bytes")
    expect(File.stat(store.blob_path(attachment_id)).mode & 0o777).to eq(0o600)
  end

  it "raises when the store is locked" do
    store.write(attachment_id, "bytes")
    Pando::Store.lock!

    expect { store.read(attachment_id) }.to raise_error(Pando::Store::Locked)
  ensure
    Pando::Store.data_key = TEST_DATA_KEY
  end

  it "tracks partial chunks by existence and purges them" do
    store.write_partial(attachment_id, 1, "second")
    store.write_partial(attachment_id, 0, "first")
    store.write_partial(attachment_id, 0, "first-again")

    expect(store.partial_count(attachment_id)).to eq(2)
    expect(store.read_partials(attachment_id, total: 2)).to eq(%w[first second])

    store.purge_partials(attachment_id)
    expect(store.partial_count(attachment_id)).to eq(0)
  end

  it "returns nil for partials that never arrived" do
    store.write_partial(attachment_id, 0, "first")

    expect(store.read_partials(attachment_id, total: 2)).to be_nil
  end
end
