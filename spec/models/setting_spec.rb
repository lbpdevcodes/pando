# frozen_string_literal: true

RSpec.describe Pando::Setting do
  it "round-trips a value through put and get" do
    described_class.put("discoverable", "1")

    expect(described_class.get("discoverable")).to eq("1")
  end

  it "returns nil for a key never written" do
    expect(described_class.get("missing")).to be_nil
  end

  it "overwrites an existing key in place" do
    described_class.put("discoverable", "1")
    described_class.put("discoverable", "0")

    expect(described_class.get("discoverable")).to eq("0")
    expect(described_class.count).to eq(1)
  end

  it "stores only ciphertext in the database" do
    described_class.put("relay", "secret-token-value")

    raw = described_class.connection.select_value(
      "SELECT value FROM settings WHERE key = 'relay'"
    )
    expect(raw).not_to include("secret-token-value")
  end
end
