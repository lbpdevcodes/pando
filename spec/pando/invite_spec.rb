# frozen_string_literal: true

RSpec.describe Pando::Invite do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }

  it "round-trips a name and device bundle through a shareable code" do
    code = described_class.encode(bundle: bundle.to_h, name: "Alice")
    invite = described_class.decode(code)

    expect(invite.name).to eq("Alice")
    expect(Pando::Crypto::DeviceBundle.from_h(invite.bundle).verified?).to be(true)
    expect(invite.fingerprint).to eq(account.fingerprint)
  end

  it "produces codes safe to paste anywhere" do
    code = described_class.encode(bundle: bundle.to_h, name: "Alice")

    expect(code).to match(/\A[A-Za-z0-9_-]+\z/)
  end

  it "rejects garbage codes" do
    expect { described_class.decode("not an invite") }.to raise_error(described_class::Malformed)
    expect { described_class.decode("") }.to raise_error(described_class::Malformed)
  end

  it "rejects codes whose bundle does not verify" do
    tampered = bundle.to_h.merge("mailbox" => "hijacked")
    code = described_class.encode(bundle: tampered, name: "Mallory")

    expect { described_class.decode(code) }.to raise_error(described_class::Malformed)
  end
end
