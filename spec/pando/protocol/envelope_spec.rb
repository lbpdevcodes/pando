# frozen_string_literal: true

RSpec.describe Pando::Protocol::Envelope do
  let(:sender) { Pando::Crypto::Device.generate }
  let(:recipient) { Pando::Crypto::Device.generate }

  def seal(plaintext = "secret payload")
    described_class.seal(plaintext, from: sender, to: recipient.encryption_public_key)
  end

  it "seals a payload only the recipient device can open" do
    envelope = seal

    expect(envelope.open(with: recipient)).to eq("secret payload")
  end

  it "identifies the sender's mailbox and encryption key" do
    envelope = seal

    expect(envelope.from).to eq(sender.mailbox)
    expect(envelope.sender_key).to eq(sender.encryption_public_key)
  end

  it "cannot be opened by a device it was not sealed for" do
    expect { seal.open(with: Pando::Crypto::Device.generate) }
      .to raise_error(RbNaCl::CryptoError)
  end

  it "rejects tampered ciphertext" do
    tampered = seal.to_h.merge("c" => ["forged bytes"].pack("m0"))

    expect { described_class.from_h(tampered).open(with: recipient) }
      .to raise_error(RbNaCl::CryptoError)
  end

  it "round-trips through its wire form" do
    envelope = described_class.from_h(seal.to_h)

    expect(envelope.open(with: recipient)).to eq("secret payload")
    expect(envelope.from).to eq(sender.mailbox)
  end

  it "exposes no plaintext in its wire form" do
    expect(seal.to_h.values.join).not_to include("secret payload")
  end
end
