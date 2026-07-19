# frozen_string_literal: true

RSpec.describe Pando::Crypto::Trust do
  let(:key) { "pinned-public-key" }

  it "starts unverified with the pinned key" do
    trust = described_class.pin(key)

    expect(trust.level).to eq(:unverified)
  end

  it "upgrades to verified" do
    trust = described_class.pin(key).verify

    expect(trust.level).to eq(:verified)
  end

  it "keeps its level when observing the pinned key" do
    trust = described_class.pin(key).verify.observe(key)

    expect(trust.level).to eq(:verified)
  end

  it "flags a key change when observing a different key" do
    trust = described_class.pin(key).verify.observe("other-key")

    expect(trust.level).to eq(:key_changed)
  end

  it "re-pins the new key when verified after a key change" do
    trust = described_class.pin(key).observe("other-key").verify

    expect(trust.level).to eq(:verified)
    expect(trust.observe("other-key").level).to eq(:verified)
  end
end
