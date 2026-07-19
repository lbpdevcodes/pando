# frozen_string_literal: true

RSpec.describe Pando::ObserveContactKey do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }

  def contact(trust_level: "unverified", persisted: true)
    record = Pando::Contact.new(fingerprint: account.fingerprint, name: "Zoe",
      bundle: JSON.generate(bundle.to_h), trust_level: trust_level)
    record.save! if persisted
    record
  end

  it "pins a brand-new contact as unverified" do
    trust = described_class.new.call(contact(persisted: false), account.public_key)

    expect(trust.level).to eq(:unverified)
  end

  it "keeps unverified when the observed key matches an unverified pin" do
    expect(described_class.new.call(contact, account.public_key).level).to eq(:unverified)
  end

  it "keeps verified when the observed key matches a verified pin" do
    expect(described_class.new.call(contact(trust_level: "verified"), account.public_key).level)
      .to eq(:verified)
  end

  it "flags a different key as key_changed even for a verified contact" do
    stranger = Pando::Crypto::Account.generate

    trust = described_class.new.call(contact(trust_level: "verified"), stranger.public_key)

    expect(trust.level).to eq(:key_changed)
  end
end
