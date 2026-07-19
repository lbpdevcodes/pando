# frozen_string_literal: true

RSpec.describe Pando::RelayConfig do
  def create_relay(url: "http://relay.example:8787", token: nil, active: false)
    described_class.create!(name: URI(url).host, url: url, token: token, active: active)
  end

  it "keeps exactly one relay active at a time" do
    first = create_relay(url: "http://one.example:8787", active: true)
    second = create_relay(url: "http://two.example:8787")

    second.activate!

    expect(first.reload.active).to be(false)
    expect(second.reload.active).to be(true)
    expect(described_class.active_relay).to eq(second)
  end

  it "stores the token as ciphertext" do
    create_relay(token: "sekrit-token")

    raw = described_class.connection.select_value("SELECT token FROM relay_configs")
    expect(raw).not_to include("sekrit-token")
    expect(described_class.sole.token).to eq("sekrit-token")
  end

  it "rejects duplicate urls" do
    create_relay

    expect { create_relay }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
