# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pando::Relay::Directory do
  around do |example|
    Dir.mktmpdir { |dir| @db_path = File.join(dir, "relay.db") and example.run }
  end

  let(:directory) { described_class.new(@db_path) }
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }

  it "publishes a valid bundle and finds it by mailbox" do
    directory.publish(bundle.to_h)

    found = directory.bundle_for_mailbox(device.mailbox)
    expect(found.fetch("mailbox")).to eq(device.mailbox)
  end

  it "rejects bundles that do not verify" do
    tampered = bundle.to_h.merge("mailbox" => "hijacked")

    expect { directory.publish(tampered) }.to raise_error(described_class::InvalidBundle)
    expect(directory.bundle_for_mailbox("hijacked")).to be_nil
  end

  it "exposes discoverable accounts by fingerprint" do
    directory.publish(bundle.to_h, discoverable: true)

    bundles = directory.discover(fingerprint: account.fingerprint)
    expect(bundles.length).to eq(1)
    expect(bundles.first.fetch("mailbox")).to eq(device.mailbox)
  end

  it "hides undiscoverable accounts from discovery while still routing their mailboxes" do
    directory.publish(bundle.to_h, discoverable: false)

    expect(directory.discover(fingerprint: account.fingerprint)).to be_empty
    expect(directory.bundle_for_mailbox(device.mailbox)).not_to be_nil
  end

  it "replaces a republished device bundle instead of duplicating it" do
    directory.publish(bundle.to_h, discoverable: true)
    directory.publish(bundle.to_h, discoverable: true)

    expect(directory.discover(fingerprint: account.fingerprint).length).to eq(1)
  end
end
