# frozen_string_literal: true

RSpec.describe Pando::ContactDevice do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }

  it "upserts a bundle keyed by mailbox and finds the account by box key" do
    described_class.upsert_bundle(bundle)
    described_class.upsert_bundle(bundle)

    expect(described_class.count).to eq(1)
    expect(described_class.fingerprint_for_box_key(device.encryption_public_key))
      .to eq(account.fingerprint)
  end

  it "returns every sealed-to-able bundle for a fingerprint" do
    second_device = Pando::Crypto::Device.generate
    described_class.upsert_bundle(bundle)
    described_class.upsert_bundle(
      Pando::Crypto::DeviceBundle.issue(device: second_device, account: account)
    )
    described_class.create!(fingerprint: account.fingerprint, mailbox: "known-but-unannounced",
      box_key: "AAAA")

    bundles = described_class.bundles_for(account.fingerprint)

    expect(bundles.map(&:mailbox)).to match_array([device.mailbox, second_device.mailbox])
  end

  it "lazily seeds from a legacy contact bundle on first read" do
    Pando::Contact.create!(fingerprint: account.fingerprint, name: "Zoe",
      bundle: JSON.generate(bundle.to_h))

    bundles = described_class.bundles_for(account.fingerprint)

    expect(bundles.sole.mailbox).to eq(bundle.mailbox)
    expect(described_class.count).to eq(1)
  end
end
