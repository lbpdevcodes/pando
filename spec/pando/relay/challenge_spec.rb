# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pando::Relay::Challenge do
  around do |example|
    Dir.mktmpdir { |dir| @db_path = File.join(dir, "relay.db") and example.run }
  end

  let(:directory) { Pando::Relay::Directory.new(@db_path) }
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:challenge) { described_class.new }

  def publish!
    directory.publish(Pando::Crypto::DeviceBundle.issue(device: device, account: account).to_h)
  end

  def proof(signing_device: device, mailbox: device.mailbox)
    Pando::Protocol::SubscribeProof.sign(device: signing_device, nonce: challenge.nonce, mailbox: mailbox)
  end

  it "accepts a proof from the published owner of the mailbox" do
    publish!

    expect(
      challenge.proof_valid?(mailbox: device.mailbox, device_key: device.signing_public_key,
        sig: proof, directory: directory)
    ).to be(true)
  end

  it "rejects a proof when the mailbox was never published" do
    expect(
      challenge.proof_valid?(mailbox: device.mailbox, device_key: device.signing_public_key,
        sig: proof, directory: directory)
    ).to be(false)
  end

  it "rejects a proof signed by a different device" do
    publish!
    imposter = Pando::Crypto::Device.generate

    expect(
      challenge.proof_valid?(mailbox: device.mailbox, device_key: imposter.signing_public_key,
        sig: proof(signing_device: imposter), directory: directory)
    ).to be(false)
  end

  it "rejects a proof for a different nonce" do
    publish!
    other = described_class.new
    stale = Pando::Protocol::SubscribeProof.sign(device: device, nonce: other.nonce, mailbox: device.mailbox)

    expect(
      challenge.proof_valid?(mailbox: device.mailbox, device_key: device.signing_public_key,
        sig: stale, directory: directory)
    ).to be(false)
  end

  it "expires" do
    expect(challenge.expired?(now: Time.now.to_i)).to be(false)
    expect(challenge.expired?(now: Time.now.to_i + 31)).to be(true)
  end
end
