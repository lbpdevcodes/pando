# frozen_string_literal: true

RSpec.describe Pando::ContactRequest do
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }

  def build_request(overrides = {})
    described_class.new({
      fingerprint: account.fingerprint, direction: "incoming", name: "Zoe",
      bundle: JSON.generate(bundle.to_h), status: "pending", content_id: "req-1"
    }.merge(overrides))
  end

  it "accepts a valid incoming request" do
    expect(build_request).to be_valid
  end

  it "rejects unknown directions and statuses" do
    expect(build_request(direction: "sideways")).not_to be_valid
    expect(build_request(status: "maybe")).not_to be_valid
  end

  it "allows one row per peer per direction" do
    build_request.save!

    expect { build_request(content_id: "req-2").save! }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "parses the stored bundle back into a device bundle" do
    expect(build_request.device_bundle.fingerprint).to eq(account.fingerprint)
  end

  it "lists only pending incoming requests in the inbox" do
    build_request.save!
    build_request(fingerprint: "aaaa000011112222", direction: "outgoing", content_id: "r2").save!
    build_request(fingerprint: "bbbb000011112222", status: "declined", content_id: "r3").save!

    expect(described_class.inbox.pluck(:fingerprint)).to eq([account.fingerprint])
  end

  it "stores only ciphertext for name and bundle" do
    build_request.save!

    raw = described_class.connection.select_one("SELECT name, bundle FROM contact_requests")
    expect(raw["name"]).not_to include("Zoe")
    expect(raw["bundle"]).not_to include(bundle.mailbox)
  end
end
