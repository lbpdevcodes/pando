# frozen_string_literal: true

RSpec.describe Pando::Crypto::DeviceBundle do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }

  it "issues a bundle that verifies against its account" do
    bundle = described_class.issue(device: device, account: account)

    expect(bundle.verified?).to be(true)
    expect(bundle.fingerprint).to eq(account.fingerprint)
    expect(bundle.mailbox).to eq(device.mailbox)
  end

  it "round-trips through its wire form" do
    bundle = described_class.issue(device: device, account: account)
    restored = described_class.from_h(bundle.to_h)

    expect(restored.verified?).to be(true)
    expect(restored.mailbox).to eq(bundle.mailbox)
    expect(restored.fingerprint).to eq(bundle.fingerprint)
  end

  it "fails verification when any field is tampered with" do
    tampered = described_class.issue(device: device, account: account)
      .to_h.merge("mailbox" => "hijacked")

    expect(described_class.from_h(tampered).verified?).to be(false)
  end

  it "fails verification when signed by a different account" do
    forged = described_class.issue(device: device, account: Pando::Crypto::Account.generate)
      .to_h.merge("account" => [account.public_key].pack("m0"))

    expect(described_class.from_h(forged).verified?).to be(false)
  end
end
