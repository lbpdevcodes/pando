# frozen_string_literal: true

RSpec.describe Pando::Crypto::Fingerprint do
  it "derives sixteen lowercase hex characters from public key bytes" do
    fingerprint = described_class.of("some public key bytes")

    expect(fingerprint).to match(/\A[0-9a-f]{16}\z/)
  end

  it "is stable for the same bytes" do
    expect(described_class.of("key")).to eq(described_class.of("key"))
  end

  it "differs for different bytes" do
    expect(described_class.of("one")).not_to eq(described_class.of("two"))
  end
end
