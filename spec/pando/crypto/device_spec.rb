# frozen_string_literal: true

RSpec.describe Pando::Crypto::Device do
  it "generates devices with distinct mailboxes" do
    expect(described_class.generate.mailbox).not_to eq(described_class.generate.mailbox)
  end

  it "signs messages that verify against its public signing key" do
    device = described_class.generate
    signature = device.sign("challenge")

    verify_key = RbNaCl::VerifyKey.new(device.signing_public_key)
    expect(verify_key.verify(signature, "challenge")).to be(true)
  end

  it "exposes distinct signing and encryption public keys" do
    device = described_class.generate

    expect(device.signing_public_key).not_to eq(device.encryption_public_key)
    expect(device.signing_public_key.bytesize).to eq(32)
    expect(device.encryption_public_key.bytesize).to eq(32)
  end
end
