# frozen_string_literal: true

RSpec.describe Pando::Crypto::Account do
  it "generates accounts with distinct fingerprints" do
    expect(described_class.generate.fingerprint).not_to eq(described_class.generate.fingerprint)
  end

  it "signs messages that verify against its public key" do
    account = described_class.generate
    signature = account.sign("hello")

    expect(account.verify("hello", signature)).to be(true)
  end

  it "rejects signatures over tampered messages" do
    account = described_class.generate
    signature = account.sign("hello")

    expect(account.verify("tampered", signature)).to be(false)
  end

  it "round-trips through its seed" do
    account = described_class.generate
    restored = described_class.from_seed(account.seed)

    expect(restored.fingerprint).to eq(account.fingerprint)
    expect(account.verify("hello", restored.sign("hello"))).to be(true)
  end
end
